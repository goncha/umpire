$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), "lib")))

require "umpire"
require "umpire/web"

run Umpire::Web
