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

class Note
  attr_accessor :time,:title,:summary,:id
  def initialize(title='New Note',summary='New Note')
    @id=0
    @title=title
    @summary=summary
    @time=(Time.now-978307200).to_i # Correct to iPhone epoch
    @body=@title+"\n"+@summary
  end

  def self.load(id)
    puts "Loading note..."
    result=$db.get_first_row("SELECT creation_date,title,summary FROM Note WHERE ROWID=#{id};")
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
    note.rawbody=$db.get_first_value("SELECT data FROM note_bodies WHERE note_id=#{id};")
    return note
  end

  def self.load_all
    result=$db.execute("SELECT ROWID FROM Note;")
    return result.flatten.collect { |id| self.load(id) }
  end

  def self.load_title(title="")
    result=$db.execute("SELECT ROWID FROM Note WHERE title GLOB '#{title}';")
    return result.flatten.collect { |id| self.load(id) }
  end

  def save
    puts "Saving note..."
    @time=(Time.now-978307200).to_i # Correct to iPhone epoch
    if @id == 0
      $db.execute("INSERT INTO Note (creation_date,title,summary) VALUES('#{@time}','#{e(@title)}','#{e(@summary)}');")
      @id = $db.get_first_value("SELECT ROWID FROM Note WHERE creation_date='#{@time}' AND title='#{e(@title)}' AND summary='#{e(@summary)}';")
      $db.execute("INSERT INTO note_bodies (note_id,data) VALUES('#{@id}','#{@body}');")
    else
      $db.execute("UPDATE Note SET creation_date='#{@time}',title='#{e(@title)}',summary='#{e(@summary)}' WHERE ROWID=#{@id};")
      $db.execute("UPDATE note_bodies SET data='#{e(@body)}' WHERE note_id=#{@id}")
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
    @body.gsub(/^[^<]*<div><br class="webkit-block-placeholder"><\/div>/,'').gsub(/(<[\/]?div>)+/,"\n").gsub(/&lt;/,'<').gsub(/&gt;/,'>').gsub(/&amp;/,'&').gsub(/\\\\/,'\\').gsub(/''/,"'").gsub(/ /,' ').gsub(/<br[^>]*>/,"")
  end

  def body=(text)
    unless text.nil?
      # Replace all leading spaces with non-breaking spaces
      text=text.split("\n").collect do |line|
        #while line =~ /^((\&nbsp)*)[ ][ ]/ do line = line.gsub(/^((\&nbsp)*)[ ]/,'\1&nbsp') end
        #line = line.gsub(/^((\&nbsp)*)[ ]/,'\1&nbsp ')
        line = line.gsub(/[ ][ ]/,"  ")
        line
      end
      # Surround each line in its own <div>
      text="<div>"+text.join("</div><div>")+"</div>"
      # Add a <br> to all empty lines
      text=text.gsub(/<div><\/div>/,"<div><br></div>")
    end
    text="#{@title}<div><br class=\"webkit-block-placeholder\"></div>"+text
    # SQL escape
    #text=text.gsub(/\\/, '\\\\').gsub(/'/, "''")
    #text=SQLite3::Database.quote(text)

    @body=text
  end

  def rawbody
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
  TODO = :todo
  DONE = :done
  CANCELLED = :cancelled
  DEFERRED = :deferred
  WAITING = :waiting
  PROJECT = :project
  CATEGORY = :category

  VIM_OUTLINE = { :todo      => '--',
                  :done      => '\-',
                  :cancelled => '++',
                  :deferred  => '->',
                  :waiting   => '?-',
                  :project   => '',
                  :category  => '@@'
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
    task.children = f_vo(lines)
    return task
  end

  def self.f_vo(lines,indent=2,baselevel=0)
    items = []
    while $index < lines.length do
      line = lines[$index]
      $index += 1

      next_level = baselevel
      next_level = lines[$index].scan(/^[ ]*/)[0].length / indent unless lines[$index].nil?

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
        todo.children = f_vo(lines,indent,next_level) if next_level > baselevel
      end

      next_level = baselevel
      next_level = lines[$index].scan(/^[ ]*/)[0].length / indent unless lines[$index].nil?

      items.push << todo unless todo.nil?
      break if next_level < baselevel
    end

    return items
  end

  def to_s
    return to_vo
  end
end

def to_iPhoneNote(todo)
  
end

#Note.load_all.each {|x| puts x.to_s }
#Note.load_title("Todo List").each {|x| puts x.body ; x.delete}
#puts Note.load_title("Todo")[0].body
#puts ToDoItem.new.to_vo
#puts ToDoItem.f_vo("    -- Make amazing").to_s
#note = Note.new("Todo List","Computer Todo List")
#note = Note.load_title("Todo List")[0]
#note.body = IO.readlines('/home/mra13/todo.txt').join
#puts note.to_s
#puts note.body
#note.save

def push
system 'cp '+$todopath+' '+$todopath+'.bak'
system 'cp '+$todopath+' '+$todopath+'.latest'
b=ToDoItem.load_vo($todopath)
a=b.children
#puts a.to_s
#puts a.inspect
puts '-'*50
start = {}
a.compact.delete_if{|x|x.status!=:category}.each do |category|
  note = Note.load_title("ToDo @#{category.data}")[0]
  note = Note.new("ToDo @#{category.data}",ToDoItem::VIM_OUTLINE[:category]+category.data) if note.nil?
  #start[note.title] = category.to_s
  note.body = category.to_s
  puts note.rawbody
  puts '-'*50
  note.save
end

end

#puts b.to_vo
#puts '-'*30


def pull

b=ToDoItem.load_vo($todopath)
a=b.children
finish = {}

Note.load_title("ToDo @*").each do |note|
  puts '-'*20
  puts note.to_s.chomp
  puts '-'*10
  puts note.rawbody
  puts '-'*10
  #puts note.body
  #puts
  finish[note.title] = note.body
end

#puts '-'*30

#puts "@priority"
#puts Note.load_title("ToDo @priority")[0].body

puts '-'*30
todo_txt = File.open($todopath+'.new','w+')

a.flatten.compact.each do |cat|
  puts finish["ToDo @"+cat.data]+"\n"
  todo_txt.write(finish["ToDo @"+cat.data]+"\n")
end
todo_txt.flush
todo_txt.close

puts '-'*30

end

def sync
  common = IO.readlines($todopath+'.latest')
  local = IO.readlines($todopath)

  pull

  remote = IO.readlines($todopath+'.new')

  todo = File.open($todopath,'w+')
  todo.write(Merge3::three_way(common.join,local.join,remote.join))
  todo.flush
  todo.close

  push
end

# Push to iPhone
#push

# Pull from iPhone
#pull

# Push .new to database
#File.rename($todopath,$todopath+'.tmp')
#File.rename($todopath+'.new',$todopath)
#push
#File.rename($todopath+'.tmp',$todopath)

# Sync with iPhone
sync
