#!/usr/bin/ruby

require 'sqlite3'
require 'cgi'
require 'rubygems'
require 'merge3'

debug = false

if File.exist? '/mnt/iphone/mount.sh'
  puts "iPhone FS not mounted!"
  exit 1 unless debug
end

if debug
  testdir = "/home/mra13/Projects/Michael's Code/Organization/ToDo List/testdata"
  dbpath = testdir+'/iphone-notes.db'
  $todopath = testdir+'/todo1.txt'
else
  dbpath = '/mnt/iphone/var/mobile/Library/Notes/notes.db'
  $todopath = '/home/mra13/todo.txt'
end
puts "Loading database..."
$db = SQLite3::Database.new(dbpath)
puts "done"

#TODO: Add Sync table if it doesn't already exist
# CREATE TABLE Sync (note_id INTEGER,sync_date INTEGER,unique(note_id));
#TODO: Verify schema and Note/note_body pairs?

class Note
  attr_accessor :time,:synctime,:title,:summary,:id
  def initialize(title='New Note',summary='New Note')
    @id=0
    @title=title
    @summary=summary
    @time=(Time.now-978307200).to_i # Correct to iPhone epoch
    @synctime=0
    @body=@title+"\n"+@summary
  end

  def self.load(id,lazy=false)
    puts "Loading note..."
    result=$db.get_first_row("SELECT creation_date,title,summary,sync_date FROM Note LEFT JOIN Sync ON Sync.note_id = Note.ROWID WHERE Note.ROWID=#{id};")
    puts "done"
    if result == []
      puts "Not found"
      return nil
    end
    note = self.new()
    note.id = id
    note.time = result[0]
    note.title = result[1]
    puts "Loaded #{note.title}"
    note.summary = result[2]
    note.synctime = result[3]
    note.synctime = 0 if note.synctime.nil?
    note.rawbody = nil
    load_body unless lazy
    return note
  end

  def load_body
    puts "Fetching Note body..."
    @body=$db.get_first_value("SELECT data FROM note_bodies WHERE note_id=#{@id};")
    @body="" if @body.nil?
  end

  def self.load_all
    result=$db.execute("SELECT ROWID FROM Note;")
    return result.flatten.collect { |id| self.load(id,true) }
  end

  def self.load_title(title="")
    result=$db.execute("SELECT ROWID FROM Note WHERE title GLOB '#{title}';")
    return result.flatten.collect { |id| self.load(id,true) }
  end

  def save
    puts "Saving note..."
    @time=(Time.now-978307200).to_i # Correct to iPhone epoch
    if @id == 0
      $db.transaction do |db|
        db.execute("INSERT INTO Note (creation_date,title,summary) VALUES('#{@time}','#{e(@title)}','#{e(@summary)}');")
        @id = db.get_first_value("SELECT ROWID FROM Note WHERE creation_date='#{@time}' AND title='#{e(@title)}' AND summary='#{e(@summary)}';")
        db.execute("INSERT INTO note_bodies (note_id,data) VALUES('#{@id}','#{e(@body)}');")
        db.execute("INSERT OR REPLACE INTO Sync (note_id,sync_date) VALUES(#{@id},#{@time});")
      end
    else
      $db.transaction do |db|
        db.execute("UPDATE Note SET creation_date='#{@time}',title='#{e(@title)}',summary='#{e(@summary)}' WHERE ROWID=#{@id};")
        db.execute("UPDATE note_bodies SET data='#{e(@body)}' WHERE note_id=#{@id}")
        db.execute("INSERT OR REPLACE INTO Sync (note_id,sync_date) VALUES(#{@id},#{@time});")
      end
    end
    puts "done"
  end

  def delete
    puts "Deleting note..."
    $db.execute("DELETE FROM Note WHERE ROWID=#{@id};")
    puts "done"
    @id=0
    return self
  end

  def body
    # Grab body from database if not already loaded
    text = rawbody
    # Title/Summary Header
    text = text.gsub(/^[^<]*<div><br class="webkit-block-placeholder"><\/div>/,'')
    # HTML tags
    text = text.gsub(/<\/div><div>/,"\n").gsub(/<[\/]?((div)|(br)|(span))[^>]*[\/]?>/,"")
    # Escaped HTML entities
    text = text.gsub(/&lt;/,'<').gsub(/&gt;/,'>').gsub(/&amp;/,'&')
    # Escaped quotes
    text = text.gsub(/''/,"'")
    # Non-breaking spaces
    text = text.gsub(/ /,' ')
    return text
  end

  def body=(text)
    unless text.nil?
      # Replace all pairs of spaces with &nbsp;<space>
      text=text.split("\n").collect{|x|x.gsub(/[ ][ ]/,"  ")}
      # Surround each line in its own <div>
      text="<div>"+text.join("</div><div>")+"</div>"
      # Add a <br> to all empty lines
      text=text.gsub(/<div><\/div>/,"<div><br class=\"webkit-block-placeholder\"></div>")
    end
    # Prepend title and a blank line
    text="#{@title}<div><br class=\"webkit-block-placeholder\"></div>"+text

    @body=text
  end

  def rawbody
    load_body if @body.nil?
    @body
  end

  def rawbody=(body)
    @body=body
  end

  def to_s
    return "#{@title}: #{@summary}"
  end

  private
    def e(text)
      SQLite3::Database.quote(text)
    end
end

class ToDoItem
  VIM_OUTLINE = { :todo      => '--',
                  :done      => '\-',
                  :cancelled => '++',
                  :deferred  => '->',
                  :waiting   => '?-',
                  :priority  => '!-',
                  :project   => '',
                  :category  => '@@'
                }

  VIM_OUTLINE_STYLE = { :todo      => '',
                        :done      => 'color:#666',
                        :cancelled => 'color:#666',
                        :deferred  => 'color:#666',
                        :waiting   => 'color:#666',
                        :priority  => 'color:#990000',
                        :project   => 'font-weight:bold;',
                        :category  => ''
                      }

  attr_accessor :status,:data,:children

  def initialize
    @status = :todo
    @data = "New ToDoItem"
    @children = []
  end

  def to_taskpaper
  end

  def self.f_taskpaper
  end

  def to_vo(indent='')
    s = indent+VIM_OUTLINE[@status]
    s += " " unless @status == :project || @status == :category
    s += @data+"\n"
    s += @children.compact.collect{ |c| c.to_vo(indent+'  ') }.flatten.join('')
    return s
  end

  def self.load_vo(file)
    lines = IO.readlines(file)
    $index = 0
    task = new
    task.data = "Imported Tasks"
    task.children = parse_vo(lines)
    return task
  end

  def self.parse_vo(lines,baselevel=0)
    items = []
    while $index < lines.length do
      line = lines[$index]
      $index += 1

      next_level = baselevel
      next_level = lines[$index].scan(/^[ ]*/)[0].length unless lines[$index].nil?

      todo = nil
      unless line.length == 0 || line.chomp.length == 0 || line.chomp.strip.length == 0
        todo = new
        line = line.chomp.strip
        if VIM_OUTLINE.invert.has_key? line[0..1]
          todo.status = VIM_OUTLINE.invert[line[0..1]]
          todo.data = line[2..-1].strip
        else
          # If no status characters, assume this is a project
          todo.status = :project
          todo.data = line
        end
        todo.children = parse_vo(lines,next_level) if next_level > baselevel
      end

      next_level = baselevel
      next_level = lines[$index].scan(/^[ ]*/)[0].length unless lines[$index].nil?

      items.push << todo unless todo.nil?
      break if next_level < baselevel
    end

    return items
  end

  def to_s
    return to_vo
  end
end

def stylize(text)
  ToDoItem::VIM_OUTLINE.keys.each do |tag|
    text = text.gsub(/<div>([  ]*#{Regexp.escape(ToDoItem::VIM_OUTLINE[tag])}[^<]+)<\/div>/,
                     "<div><span style=\"#{ToDoItem::VIM_OUTLINE_STYLE[tag]}\">\1</span></div>")
    puts text
    puts '-'*10
  end
  puts text
end

#Note.load_all.each {|x| puts x.to_s }
#Note.load_title("Todo List").each {|x| puts x.body ; x.delete}
#puts Note.load_title("Todo")[0].body
#puts ToDoItem.new.to_vo
#puts ToDoItem.parse_vo("    -- Make amazing").to_s
#note = Note.new("Todo List","Computer Todo List")
#note = Note.load_title("Todo List")[0]
#note.body = IO.readlines('/home/mra13/todo.txt').join
#puts note.to_s
#puts note.body
#note.save

def push(force=false)
  puts '-'*50
  puts "Pushing local ToDo items to iPhone"
  puts '-'*50
  date = Time.now.strftime('%Y.%m.%d-%H.%M.%S')
  # Backup todo.txt before we push it
  system 'cp "'+$todopath+'" "'+$todopath+'.bak-'+date+'"'
  system 'cp "'+$todopath+'" "'+$todopath+'.latest"'

  # Write each ToDoItem to an iPhone Note
  ToDoItem.load_vo($todopath).children.compact.delete_if{|x|x.status!=:category}.each do |category|
    note = Note.load_title("ToDo @#{category.data}")[0]
    note = Note.new("ToDo @#{category.data}",ToDoItem::VIM_OUTLINE[:category]+category.data) if note.nil?
    if force || note.body.chomp.strip != category.to_s.chomp.strip
      puts '-'*50
      note.body = category.to_s
      puts note.rawbody
      puts '-'*50
      note.save
    else
      puts "Note body unchanged. Forget writing that again!"
    end
  end
end



def pull
  finish = {}
  latest_times = {}
  puts '-'*50
  puts "Grabbing latest data from iPhone"
  puts '-'*50

  # Load Notes
  puts "Loading all ToDo Notes..."
  puts '-'*10
  notes = Note.load_title("ToDo @*")
  puts '-'*10
  puts "Loading modified Note bodies..."
  notes.each do |note|
    puts '-'*20
    puts note.to_s.split("\n")[0]
    unless note.time == note.synctime
      puts '-'*10
      puts note.rawbody
      finish[note.title] = note.body
    else
      puts "Note unchanged since last sync. Using cache..."
      finish[note.title] = nil
    end
  end

  puts '-'*20
  puts "Saving iPhone Notes to "+$todopath+'.pulled'
  todo_txt = File.open($todopath+'.pulled','w+')

  # Write notes locally in existing order
  ToDoItem.load_vo($todopath).children.flatten.compact.each do |cat|
    data = finish.delete("ToDo @"+cat.data)
    puts '-'*20
    if data.nil?
      puts '-'*10 + "(From cache)" + '-'*10
      puts data = cat.to_s.chomp
    else
      puts data = data.chomp
    end
    todo_txt.write(data+"\n\n\n")
  end
  
  # Are there any Note-ToDoItems that we didn't write?
  # Just a failsafe check
  finish.keys.each do |todo|
    puts '*'*50
    puts "Exists ONLY on iPhone!!!"
    puts todo
    puts '*'*50
    puts data = finish[todo].chomp+"\n\n\n"
    todo_txt.write(data)
  end

  todo_txt.flush
  todo_txt.close

  puts '-'*20
  puts "Data saved to"+$todopath+'.pulled'

end

def sync
  common = IO.readlines($todopath+'.latest')
  local = IO.readlines($todopath)

  pull

  remote = IO.readlines($todopath+'.pulled')

  puts "Merging changes..."
  #merged = Merge3::three_way(common.join,local.join,remote.join)
  merged = `/usr/bin/env diff3 -m --easy-only #{$todopath} #{$todopath+'.latest'} #{$todopath+'.pulled'}`
  puts "done"

  if merged.chomp.strip.length == 0
    puts "Merge error? Or maybe just no changes..."
    exit 1
  end

  # Save changes to local file
  todo = File.open($todopath,'w+')
  todo.write(merged)
  todo.flush
  todo.close

  push
end

# Push to iPhone
#push true

# Pull from iPhone
#pull

# Push .new to database
#File.rename($todopath,$todopath+'.tmp')
#File.rename($todopath+'.new',$todopath)
#push true
#File.rename($todopath+'.tmp',$todopath)

# Sync with iPhone
sync
