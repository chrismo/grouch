#!/usr/bin/ruby

# modified version of
#
# https://github.com/semaperepelitsa/osx-trash/blob/master/bin/trash
# == Author
# Dave Dribin
#
# == Copyright
# Copyright (c)  2008 Dave Dribin
# Licensed under the MIT license.

require 'pathname'
require 'optparse'
require 'ostruct'

require 'osx/cocoa'
include OSX
OSX.require_framework 'ScriptingBridge'

class OSXTrash
  def initialize
    @finder = create_finder
  end

  def create_finder
    stderr = $stderr.clone # save current STDERR IO instance
    $stderr.reopen('/dev/null', 'w') # send STDERR to /dev/null
    finder = SBApplication.applicationWithBundleIdentifier("com.apple.Finder")
    $stderr.reopen(stderr) # revert to default behavior
    return finder
  end

  def list
    trash = @finder.trash
    trash.items.each do |item|
      file_url = NSURL.URLWithString(item.URL)
      Pathname item_path = Pathname.new(file_url.path)
      if block_given?
        yield item
      else
        puts item_path
      end
    end
  end

  def find(search)
    i = 0
    list do |item|
      print '.' if i.divmod(100)[1] == 0
      i += 1
      #file_url = NSURL.URLWithString(item.URL)
      #Pathname item_path = Pathname.new(file_url.path)
      return item if item.URL.to_s =~ /#{search}/
    end
  end
end
