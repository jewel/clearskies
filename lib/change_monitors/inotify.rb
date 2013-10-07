require 'fiddle'
require 'fiddle/import'

module LibNotify
  extend Fiddle::Importer
  #TODO: do this in a distro independent way
  dlload '/lib/x86_64-linux-gnu/libc.so.6'
  extern 'int inotify_init()'
  extern 'int inotify_add_watch(int, const char*, unsigned int)' #fd, pathname, mask
  extern 'int inotify_rm_watch(int, int)' # fd, wd
end
