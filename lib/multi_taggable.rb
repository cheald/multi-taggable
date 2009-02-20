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
					write_inheritable_attribute(:multi_tagging_groups, options[:groups] || {})
					unless options[:groups].nil?
						options[:groups].each do |key, group|
							has_many key, :class_name => "MultiTagging", :conditions => ["multi_taggings.context IN (?)", group], :as => :taggable
						end
					end
					
					def multi_tagging_groups
						self.class.read_inheritable_attribute(:multi_tagging_groups)
					end
				end
				
				include ClassMethods
			end
		end
		
		module ClassMethods
			def self.included(klass)
				klass.class_eval do
					include MultiTaggable::InstanceMethods
					
					has_many :multi_taggings, :as => :taggable
					has_many :multi_tags, :through => :multi_taggings
					
					after_save :save_tags
					
					named_scope :multi_tagged, lambda {|tags, context, tagger|
						return {} if tags.nil?
						tag_ids = MultiTag.all(:conditions => ["name in (?)", tags])
						
						# If we couldn't find all the tags we asked for, just cut it short - we can't match them all, so we return nothing.
						return {:conditions => "false"} if tag_ids.length != tags.length
						
						opts = {
							:joins => "inner join multi_taggings on multi_taggings.taggable_type = \"#{self.to_s}\" and multi_taggings.taggable_id = #{self.table_name}.id",
							:conditions => ["multi_taggings.multi_tag_id in (?)", tag_ids]
						}
						if tag_ids.length > 0 then
							opts[:group] = "#{self.table_name}.id having count(distinct multi_taggings.multi_tag_id) = #{tags.length}"
						end
						
						unless context.nil?
							if context.is_a?(Array)
								opts[:conditions][0] += " and multi_taggings.context in (?)"
							elsif context.is_a?(String)
								opts[:conditions][0] += " and multi_taggings.context = ?"
							end
							opts[:conditions].push context
						end
						
						if tagger.is_a?(ActiveRecord::Base)
							opts[:conditions] += " and multi_taggings.tagger_type = ? and multi_taggings.tagger_id = ?"
							opts[:conditions].push tagger.class.to_s
							opts[:conditions].push tagger.id
						end

						return opts
					}
				end
			end
		end
		
		module InstanceMethods
			def set_multi_tag_list(list, context, tagger = :multi_taggable_default_tagger)
				init_or_get_tag_list(context, tagger).update(list)
			end
			
			def multi_tag_list(context, tagger = :multi_taggable_default_tagger)
				init_or_get_tag_list(context, tagger)
			end
			
			def multi_tag_counts(context = nil, tagger = nil)
				multi_taggings.by_context(context).by_tagger(tagger).all(
					:select => "multi_taggings.*, count(id) as count",
					:group => "multi_tag_id"
				).inject({}) {|h, r| h[r.name] = r.count; h}
			end
			
			protected
			
			def init_or_get_tag_list(context, tagger)
				@multi_tag_lists ||= {}
				@multi_tag_lists[context] ||= {}
				
				if @multi_tag_lists[context][tagger].nil? then
					 conditions = ["context = ?", context]
					 if tagger.is_a?(ActiveRecord::Base) then
						conditions[0] += " and tagger_type = ? and tagger_id = ?"
						conditions.push tagger.class.to_s
						conditions.push tagger.id
					 end
					@multi_tag_lists[context][tagger] = TagList.new(multi_taggings.all(:conditions => conditions).map(&:name))
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
								MultiTagging.delete_all(["taggable_id = ? and taggable_type = ? and context #{sql_eq(context)} ? and tagger_id #{sql_eq(tagger_id)} ? and name not in (?)", self.id, self.class.base_class.to_s, context, tagger_id, list])
								
								# Add tags that were not in the original set
								existing_tags = multi_taggings.all(:conditions => ["taggable_type = ? and context #{sql_eq(context)} ? and tagger_id #{sql_eq(tagger_id)} ? and name in (?)", self.class.base_class.to_s, context, tagger_id, list]).map {|t| t.name.downcase }
								list.each do |tag|
									downcase_tag = tag.downcase
									unless existing_tags.include?(downcase_tag)
										tag_instance = MultiTag.find_or_create_by_name(downcase_tag)
										multi_taggings.create(:context => context, :tagger => tagger, :name => tag, :multi_tag_id => tag_instance.id, :taggable_type => self.class.base_class.to_s)
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