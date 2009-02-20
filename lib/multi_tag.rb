class MultiTag < ActiveRecord::Base
	has_many :multi_taggings, :dependent => :destroy
	validates_uniqueness_of :name
	validates_presence_of :name
end