class MultiTagging < ActiveRecord::Base
	belongs_to :multi_tag
	belongs_to :taggable, :polymorphic => true
	belongs_to :tagger, :polymorphic => true
	
	named_scope :by_context, lambda {|context|
		return {} if context.nil?
		return {:conditions => ["context = ?", context]}
	}

	named_scope :by_tagger, lambda {|tagger|
		return {} if tagger.nil?
		return {:conditions => ["tagger_type = ? and tagger_id = ?", tagger.class.to_s, tagger.id]}
	}
	
	named_scope :for_taggables, lambda {|type, taggables|
		{ :conditions => ["taggable_type = ? and taggable_id in (?)", type, taggables] }
	}
	
	def self.count_for_taggables(taggables, context = nil, tagger = nil)
		klass, ids = taggables.first.class.base_class.to_s, taggables.map(&:id)
		self.by_context(context).by_tagger(tagger).for_taggables(klass, ids).all(
			:select => "name, count(id) as count",
			:group => "multi_tag_id"
		)
	end
end