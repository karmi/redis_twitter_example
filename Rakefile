HTML =<<HTML
<thead>
    <tr>
      <th class=docs><h1>redis_twitter_example.sh</h1></th>
      <th class=code></th>
    </tr>
  </thead>
HTML

filename = 'redis_twitter_example.html'

task :default => 'web:generate'

namespace :web do

  desc "Update the Github website"
  task :update => :generate do
    current_branch = `git branch --no-color`.split("\n").select { |line| line =~ /^\* / }.first.to_s.gsub(/\* (.*)/, '\1')
    (puts "Unable to determine current branch"; exit(1) ) unless current_branch
    system "git checkout web"
    system "cp #{filename} index.html"
    system "git add index.html && git co -m 'Updated website'"
    system "git push origin web:gh-pages -f"
    system "git checkout #{current_branch}"
  end

  desc "Generate the Rocco documentation page"
  task :generate do
    system "rocco redis_twitter_example.sh"
    html = File.read(filename).
           gsub!(Regexp.new(Regexp.escape(HTML)), '').
           gsub!(Regexp.new('<title>redis_twitter_example.sh</title>'), '<title>Redis Twitter Example</title>')
    File.open(filename, 'w') { |f| f.write html }
    system "open #{filename}"
  end
end
