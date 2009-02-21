class Tagging < ActiveRecord::Base
	belongs_to :tag
	belongs_to :taggable, :polymorphic => true
	belongs_to :tagger, :polymorphic => true
	
	named_scope :by_context, lambda {|context, *args|
		return {} if context.nil?
		table_name = args.first
		return {:conditions => ["#{table_name + "." unless table_name.blank?}context = ?", context.to_s]}
	}

	named_scope :by_tagger, lambda {|tagger, *args|
		return {} if tagger.nil?
		table_name = args.first
		return {:conditions => ["#{table_name + "." unless table_name.blank?}tagger_type = ? and #{table_name + "." unless table_name.blank?}tagger_id = ?", tagger.class.to_s, tagger.id]}
	}
	
	named_scope :for_taggables, lambda {|type, taggables|
		{ :conditions => ["taggable_type = ? and taggable_id in (?)", type, taggables] }
	}
	
	named_scope :shared_contexts, {:select => "distinct context", :conditions => "tagger_id is null and context is not null"}
	named_scope :individual_contexts, {:select => "distinct context", :conditions => "tagger_id is not null and context is not null"}
	
	def self.count_for_taggables(taggables, options = {})
		return [] if taggables.nil? or taggables.blank?
		
		context = options.delete :context
		tagger = options.delete :tagger
		
		klass, ids = taggables.first.class.base_class.to_s, taggables.map(&:id)
		self.by_context(context).by_tagger(tagger).for_taggables(klass, ids).all({
			:select => "name, count(id) as count",
			:group => "tag_id"
		}.merge(options))
	end
	
	def count
		(read_attribute(:count) || 1).to_i
	end
end