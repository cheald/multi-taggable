multi-taggable: A twisted tagging plugin for group tagging

Inspired by acts-as-taggable-on and if-taggable

*** NOTE ***
multi-taggable is unfinished. There are no tests. There are no migrations. There's
very little documentation. It's extremely volatile.

About multi-taggable

multi-taggable is a tagging plugin I wrote to address a problem that other tagging plugins don't: 
concurrent tagging by multiple users.

In short, taggings can be distinguished by both a context and a tagger. If a taggable is tagged by
multiple taggers, their tags don't clobber each other. It's possible to retrieve all tags on a
taggable at a number of granularity levels:

* All tags on a taggable
* All tags by a tagger on a taggable
* All tags in a context on a taggable
* All tags on a context by a certain tagger

Additionally, you can retrieve all taggables...

* ...with a given tag (or set of tags)
* ...with a given tag (or set of tags) in a given context
* ...with a given tag (or set of tags) by a given user
* ...with a given tag (or set of tags) in a given context by a given user

In effect, this gives you a hybrid tagging system that may function either like Delicious' tagging,
where each user may assign their own tags to an item, and those tags become a part of a cumulative
community tag cloud, or which may function like a traditional tagging system, where changes to a
taggable's tag set clobbers the previous tag set.

You don't actually have to specify a list of contexts that may be tagged on. multi-taggable doesn't
do any fancy named method generation (with the exception of meta-contexts below), which leaves it
pretty flexible at the cost of slightly clunkier syntax.

	class Bookmark < ActiveRecord::Base
		multi_taggable
	end
	
	bookmark = Bookmark.new
	# No user specified. This is the classic tagging approach
	bookmark.set_multi_tag_list("blue, green", "tags")
	
	# Allows for multi-user tagging
	bookmark.set_multi_tag_list("new, awesome, interesting", "tags", User.find(1))
	bookmark.set_multi_tag_list("dull, boring, old", "tags", User.find(2))
	bookmark.save
	
	>> bookmark.multi_tag_list("tags")
	=> ["new", "awesome", "interesting", "dull", "boring", "old"]

	>> bookmark.multi_tag_list("tags", User.find(1))
	=> ["new", "awesome", "interesting"]

You can search for taggables by multiple tags:

	# returns all Bookmarks tagged with both "foo" and "bar" by any
	# combination of users, on any context
	>> Bookmark.multi_tagged(["foo", "bar"], nil, nil).all
	
	# returns all Bookmarks tagged with both "foo" and "bar" by any
	# combination of users, on the "tags" context
	>> Bookmark.multi_tagged(["foo", "bar"], "tags", nil).all

	# returns all Bookmarks tagged with both "foo" and "bar" by User ID 1
	# on the "tags" context
	>> Bookmark.multi_tagged(["foo", "bar"], "tags", User.first(1)).all

Finally, multi-taggable provides meta-contexts composed of groups of given tag contexts. 

	class Book < ActiveRecord::Base
		multi_taggable(:groups => {
			"people" => %w"author editor publisher"
		})
	end

	book = Book.new
	book.set_multi_tag_list("author", "John Doe, Jane Doe")
	book.set_multi_tag_list("publisher", "Awesomehouse Books")
	book.save

	>> book.people
	=> ["John Doe", "Jane Doe", "Awesomehouse Books"]
	
The naming and syntax are a little clunky, but everything runs around with a multi_ prefix because
I developed this in a system with acts-as-taggable-on already integrated, and needed to avoid
collisions while I migrated over to it. That may change at some point down the road, may not, I
don't know.

Because a tagging requires multiple pieces of information, there isn't a simple setter added to the
model. You'll have to manually call #set_multi_tag_list on you model instances to set/update tags,
but hey, you get awesome functionality in exchange.