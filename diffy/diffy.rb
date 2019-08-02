require 'tempfile'
require 'erb'
require 'rbconfig'

module Diffy
  WINDOWS = RUBY_PLATFORM =~ /mswin|mingw|cygwin/
end
require 'open3' unless Diffy::WINDOWS
require_relative 'format'
require_relative 'diff'
require_relative 'split_diff'