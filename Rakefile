task :test do
  Dir.glob('./test/**/*.rb').each { |file| require file}
end

task :clean_db do
  require_relative 'lib/conf'
  FileUtils.rm_rf(Conf.data_dir, :verbose => true)
end

task :default => :test
