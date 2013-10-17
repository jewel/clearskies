task :test do
  $: << 'lib'
  Dir.glob('./test/**/*.rb').each { |file| require file}
end

task :clean_db do
  $: << 'lib'
  require 'conf'
  FileUtils.rm_rf(Conf.data_dir, :verbose => true)
end

task :default => :test
