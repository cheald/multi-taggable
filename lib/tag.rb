class Tag < ActiveRecord::Base
	has_many :taggings, :dependent => :destroy
	validates_uniqueness_of :name
	validates_presence_of :name
	
	def to_s
		name
	end
end