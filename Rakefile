task :test do
  $: << 'lib'
  Dir.glob('./test/**/*.rb').each { |file| require file}
end

task :default => :test
