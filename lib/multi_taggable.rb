module TagTeamInteractive
	module MultiTaggable
		class TagList < Array
			cattr_accessor :delimiter
			@@delimiter = ','

			def initialize(list)
				@changed = false
				update(list, true)
			end
			
			def update(list, non_mutative = false)
				@changed = true unless non_mutative
				list = list.is_a?(Array) ? list : list.split(@@delimiter).collect(&:strip)
				list.uniq!
				list.reject! {|t| t.blank? }
				replace(list)
			end
			
			def changed?
				@changed
			end
			
			def committed!
				@changed = false
			end

			def to_s
				join('#{@@delimiter} ')
			end
		end
		
		module ActiveRecordExtension
			def multi_taggable(options = {})
			
				self.class_eval do
					write_inheritable_attribute(:tagging_groups, (options[:groups] || {}).with_indifferent_access)
					unless options[:groups].nil?
						options[:groups].each do |key, group|
							has_many key, :class_name => "Tagging", :conditions => ["#{Tagging.table_name}.context IN (?)", group], :as => :taggable
						end
					end
					
					def tagging_groups(name = nil)
						self.class.read_inheritable_attribute(:tagging_groups)
					end

					def tagging_group(name)
						self.class.read_inheritable_attribute(:tagging_groups)[name] || []
					end
				end
				
				include ClassMethods
				extend SingletonMethods
			end
		end
		
		module ClassMethods
			def self.included(klass)
				klass.class_eval do
					include MultiTaggable::InstanceMethods
					
					has_many :taggings, :as => :taggable
					has_many :tags, :through => :taggings
					
					after_save :save_tags
					
					named_scope :related_to_by_tags, lambda {|taggable, *args|
						table = taggable.class.table_name
						context = args.first
						tags = taggable.tags.map &:id
						conditions = ["#{table}.id = taggings.taggable_id AND taggings.taggable_type = '#{taggable.class.base_class.to_s}' AND taggings.tag_id IN (?) AND #{table}.id != ?", tags, taggable.id]
						unless context.blank?
							conditions[0] += " AND taggings.context IN (?)"
							conditions.push context
						end
						{
							:select     => "#{table}.*, COUNT(distinct taggings.tag_id) AS count", 
							:from       => "#{table}, taggings",
							:conditions => conditions,
							:group      => "#{table}.id",
							:order      => "count DESC"
						}
					}					
					
					named_scope :tagged, lambda {|tags, options|
						return {} if tags.nil? or tags.blank?
						tag_ids = nil
						expected_tag_length = 0
						if tags.is_a?(Array)
							tag_ids = Tag.all(:conditions => ["name in (?)", tags])
							expected_tag_length = tags.length
						elsif tags.is_a?(String)
							tag_ids = Tag.all(:conditions => ["name = ?", tags])
							expected_tag_length = 1 
						end
						
						
						# If we couldn't find all the tags we asked for, just cut it short - we can't match them all, so we return nothing.
						return {:conditions => "false"} if tag_ids.length != expected_tag_length
						
						table_name = options[:table_name] || Tagging.table_name
						
						opts = {
							:joins => "inner join #{Tagging.table_name} #{table_name} on #{table_name}.taggable_type = \"#{self.to_s}\" and #{table_name}.taggable_id = #{self.table_name}.id",
							:conditions => ["#{table_name}.tag_id in (?)", tag_ids]
						}
						if tags.is_a?(Array) then
							opts[:group] = "#{self.table_name}.id having count(distinct #{table_name}.tag_id) = #{expected_tag_length}"
						end
						
						context = options[:context] || options[:on] || options[:contexts]
						unless context.nil?
							if context.is_a?(Array)
								opts[:conditions][0] += " and #{table_name}.context in (?)"
								opts[:conditions].push context.to_s
							elsif context.is_a?(String) or context.is_a?(Symbol)
								opts[:conditions][0] += " and #{table_name}.context = ?"
								opts[:conditions].push context.to_s
							end
						end
						
						tagger = options[:tagger] || options[:by] || options[:tagged_by]
						if tagger.is_a?(ActiveRecord::Base)
							opts[:conditions][0] += " and #{table_name}.tagger_type = ? and #{table_name}.tagger_id = ?"
							opts[:conditions].push tagger.class.to_s
							opts[:conditions].push tagger.id
						end
						return opts
					}
				end
			end
		end
		
		module SingletonMethods
			def tag_counts(options = {})
				scope = scope(:find)
								
				options[:conditions] = merge_conditions(options[:conditions], scope[:conditions]) if scope
				
				count_table_name = Tagging.table_name + "_for_count"
				
				options[:joins] ||= []
				options[:joins] << "LEFT OUTER JOIN #{table_name} ON #{table_name}.#{primary_key} = #{count_table_name}.taggable_id"
				options[:joins] << scope[:joins] if scope && scope[:joins]
				options[:joins] = options[:joins].join(" ")
				
				options[:from] = "#{Tagging.table_name} #{count_table_name}"
				
				options[:select] = "#{count_table_name}.name, count(#{count_table_name}.id) as count"
				options[:group] = "#{count_table_name}.tag_id"
				
				context = options.delete(:context) || options.delete(:on)
				by = options.delete(:by) || options.delete(:tagger) || options.delete(:tagged_by)
				
				Tagging.by_context(context, count_table_name).by_tagger(by, count_table_name).all(options)
			end           
		end
		
		module InstanceMethods
			def set_tag_list(list, options = {})
				context = options.delete(:context) || options.delete(:on)
				tagger = options.delete(:by) || options.delete(:tagger) || options.delete(:tagged_by) || :multi_taggable_default_tagger
				init_or_get_tag_list(context, tagger).update(list)
			end
			
			def tag_list(options = {})
				context = options.delete(:context) || options.delete(:on)
				tagger = options.delete(:by) || options.delete(:tagger) || options.delete(:tagged_by) || :multi_taggable_default_tagger
				init_or_get_tag_list(context, tagger, options)
			end
			
			def tag_counts(options = {})
				context = options.delete(:context) || options.delete(:on)
				tagger = options.delete(:by) || options.delete(:tagger) || options.delete(:tagged_by)
				
				taggings.by_context(context).by_tagger(tagger).all({
					:select => "#{Tagging.table_name}.*, count(#{Tagging.table_name}.id) as count",
					:group => "#{Tagging.table_name}.tag_id"
				}.merge(options))
			end
			
			protected
			
			def init_or_get_tag_list(context, tagger, options = {})
				@multi_tag_lists ||= {}
				context = context.to_s
				
				@multi_tag_lists[context] ||= {}
				
				if force = options.delete(:no_cache) then
					@multi_tag_lists[context][tagger] = nil
				end
				if @multi_tag_lists[context][tagger].nil? then
					 conditions = ["context = ?", context]
					 if tagger.is_a?(ActiveRecord::Base) then
						conditions[0] += " and tagger_type = ? and tagger_id = ?"
						conditions.push tagger.class.to_s
						conditions.push tagger.id
					 end
					 options[:conditions] = ActiveRecord::Base.send :merge_conditions, options[:conditions], conditions
					@multi_tag_lists[context][tagger] = TagList.new(taggings.all(options).map(&:name))
				end
				return @multi_tag_lists[context][tagger]
			end		
			
			def sql_eq(f)
				f.nil? ? "IS" : "="
			end
			
			def save_tags
				return if @multi_tag_lists.nil?
				self.class.transaction do
					@multi_tag_lists.each do |context, taggers|
						taggers.each do |tagger, list|
							tagger = tagger.is_a?(ActiveRecord::Base) ? tagger : nil
							tagger_id = case tagger
								when ActiveRecord::Base
									tagger.id
								else
									nil
							end
							
							if list.changed?					
								# Delete all tags that were in the original set, but are no longer
								Tagging.delete_all(["taggable_id = ? and taggable_type = ? and context #{sql_eq(context)} ? and tagger_id #{sql_eq(tagger_id)} ? and name not in (?)", self.id, self.class.base_class.to_s, context, tagger_id, list])
								
								# Add tags that were not in the original set
								existing_tags = taggings.all(:conditions => ["taggable_type = ? and context #{sql_eq(context)} ? and tagger_id #{sql_eq(tagger_id)} ? and name in (?)", self.class.base_class.to_s, context, tagger_id, list]).map {|t| t.name.downcase }
								list.each do |tag|
									downcase_tag = tag.downcase
									unless existing_tags.include?(downcase_tag)
										tag_instance = Tag.find_or_create_by_name(downcase_tag)
										taggings.create(:context => context, :tagger => tagger, :name => tag, :tag_id => tag_instance.id, :taggable_type => self.class.base_class.to_s)
									end
									list.committed!
								end
							end
						end
					end
				end
			end
		end
	end
end

ActiveRecord::Base.send(:extend, TagTeamInteractive::MultiTaggable::ActiveRecordExtension)