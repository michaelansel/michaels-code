#!/usr/bin/ruby

# Regular Expressions

$chapter = "C((hapter)|(HAPTER))(\ )"
$roman = """
    M{0,4}              # thousands - 0 to 4 M's
    ((CM)|(CD)|(D?C{0,3}))    # hundreds - 900 (CM), 400 (CD), 0-300 (0 to 3 C's),
                        #            or 500-800 (D, followed by 0 to 3 C's)
    ((XC)|(XL)|(L?X{0,3}))    # tens - 90 (XC), 40 (XL), 0-30 (0 to 3 X's),
                        #        or 50-80 (L, followed by 0 to 3 X's)
    ((IX)|(IV)|(V?I{0,3}))    # ones - 9 (IX), 4 (IV), 0-3 (0 to 3 I's),
                        #        or 5-8 (V, followed by 0 to 3 I's)
"""
$separator = "I?[\.:\ -_]"


def test
  rules = ['chapter','roman','separator']
  title = 'oneline'
  lines = [
           'bogus header info',
           'Chapter IV. A Title',
           'Chapter kjaslkdjfalskdjf',
           'ivlskjfs',
           'IVlskdjf',
           'I am.',
           'Chapter I: A First Chapter',
           'kljlksjdf'
          ]
  lines.size.times do
    current = lines.delete_at(0)
    puts detect_chapters(current,lines,rules,title)
  end
end


def detect_chapters(current,lines,rules,title_rule)

  regex = /(?x)^#{eval('a=$'+rules.join('+$'))}/   ## Maybe replace this with a 'build_regex' method? (for regex's that require special logic)
#puts regex
#puts /(?x)#{$chapter}#{$roman}#{$separator}/
  return nil unless current.strip =~ regex
  return send(title_rule,current,lines,regex)
end

def notitle(current,lines,regex)
  return ""
end

def oneline(current,lines,regex)
  return current.strip.gsub(regex,'')
end

def twoline(current,lines,regex)
  return current.strip.gsub(regex,'').strip
end





#test
#exit





#Chapter 19: A Walk Through the Park
def labeled_init
  $regex = /^.?C((hapter)|(HAPTER)) [0-9]{1,3}.?/
end
def labeled_chapters(current,lines)
  return current.strip.gsub($labeled_regex,'').strip if current.strip =~ $regex
  return nil
end

#_Chapter 12_   OR     Chapter 12
#Gone With the Wind
def labeled_twoline_init
  $regex = /^.?C((hapter)|(HAPTER)) [0-9]{1,3}.?/
end
def labeled_twoline_chapters(current,lines)
  return lines.delete_at(0) if current.strip =~ $regex
  return nil
end

#  1
#  2
def digits_init
  $cur_chap=1
end
def digits_chapters(current,lines)
  if current.strip == $cur_chap.to_s
    $cur_chap += 1
    return lines.delete_at(0)
  end
  return nil
end

# III. A Lost Cause
# X: Along Came a Traveler
# XIV Beyond the Door
def roman_init
  $regex = """(?x)            # turn on free-space mode
    ^                   # beginning of string
    C((hapter)|(HAPTER))(\ )  # optional CHAPTER
    M{0,4}              # thousands - 0 to 4 M's
    ((CM)|(CD)|(D?C{0,3}))    # hundreds - 900 (CM), 400 (CD), 0-300 (0 to 3 C's),
                        #            or 500-800 (D, followed by 0 to 3 C's)
    ((XC)|(XL)|(L?X{0,3}))    # tens - 90 (XC), 40 (XL), 0-30 (0 to 3 X's),
                        #        or 50-80 (L, followed by 0 to 3 X's)
    ((IX)|(IV)|(V?I{0,3}))    # ones - 9 (IX), 4 (IV), 0-3 (0 to 3 I's),
                        #        or 5-8 (V, followed by 0 to 3 I's)
    [\.:\ ]             # roman numeral is followed by period, colon, or space
    """
  $regex = /#{$regex}/
end
def roman_chapters(current,lines)
  return current.strip.gsub($regex,'').strip if current.strip =~ $regex
  return nil
end

#CHAPTERBOUNDARY
#The Hunt for Red October
def handtagged_init
end
def handtagged_chapters(current,lines)
  return lines.delete_at(0) if current =~ /CHAPTERBOUNDARY/
  return nil
end

#Charlie and the Chocolate Factory
def titlecase_init
end
def titlecase_chapters(current,lines)
  return current if current.strip =~ /^\b((([A-Z]\w*(\'s)?)|(a|an|and|at|by|for|from|in|of|or|the|to))\W*){1,10}\b$/
  return nil
end

#Chapters are manually listed in a separate file (inputfile-chapterlist.txt)
def listed_init
  $chapter_list = IO.readlines($DIR+'/'+inputfile.split(".")[0]+"-chapterlist.txt")
end
def listed_chapters(current,lines)
  $chapter_list.each do |chapter|
    return current if current.strip == chapter.strip
  end
  return nil
end

#Creates a new chapter every 500 lines
def size_init
  $size_limit = 500
end
def size_chapters(current,lines)
  return nil
end


#Example Chapter Line
def blank_init
  # This is run once at the very beginning
  # It is for setting up any variables or loading files
end
def blank_chapters(current,lines)
  # If this line is a chapter boundary
  return "detected chapter title" if true
  # Otherwise, return nil
  return nil
end





def do_chapter_detection(current,lines,chapter_type)
  return send(chapter_type+"_chapters",current,lines)
end

def save_chapter(outputname,chapternum,chapter_title,chapterlines)
    puts chapter_title
    #Save chapter
    chapterfile = File.open($DIR+'/'+"#{sprintf('%0.3d',chapternum)} - #{eval(outputname)}.txt",'w+')
    chapterfile.write(chapter_title)
    chapterfile.write(chapterlines[0])
    chapterlines.size.times do |chapterlinenum|
      # The +1 below fixes an off-by-one error that truncated the last line (paragraph) of every chapter
      chapterfile.write(chapterlines[chapterlinenum+1])
    end
    chapterfile.flush
    chapterfile.close
end

def control? code
  if code.nil?
    return false
  end
  control_codes = "AUTO-OFF,AUTO-ON"
  control_codes.include? code.chomp
end

def control! code
  if code =~ /AUTO-OFF/
    auto_split = false
  end
  if code =~ /AUTO-ON/
    auto_split = true
  end
end







# BEGIN MAIN CODE
$DIR = File.dirname(File.expand_path(__FILE__))
abort "usage: split.rb inputfile.txt [chapter type]" if ARGV.size < 1 and not File.exist? $DIR+'/split.yaml'

# Defaults
chapternum = 0
chapter_line_num = 0
chapterlines = {}
chapter_title = "Header Information\n"
chapter_type = "titlecase"
outputname = '$inputfile.split(".")[0]'
$auto_split = true

# Command line arguments
$inputfile = ARGV[0] if ARGV.size >= 1
puts ARGV[0].split(".")[0] if ARGV.size >= 1
chapter_type = ARGV[1] if ARGV.size >= 2

# Configuration file
if File.exist? $DIR+'/split.yaml'
  require 'yaml'
  config = YAML.load_file($DIR+"/split.yaml")

  #Input settings
  if config["input"]
    $inputfile = config["input"]["filename"] if config["input"]["filename"]
    chapter_type = config["input"]["chapter type"] if config["input"]["chapter type"]
  end

  #Output settings
  if config["output"]
    outputname = 'aavkjwlkfjf = "'+config["output"]["name"]+'"' if config["output"]["name"]
    outputname = config["output"]["name_code"] if config["output"]["name_code"]
  end

end

# Sanity check
if $inputfile.nil? or chapter_type.nil?
  abort "You must specify a filename and a chapter split type"
end

# Read book into memory
lines = IO.readlines $DIR+'/'+$inputfile

# Sanity check
if lines.nil?
  abort "The book file is empty!"
end

# Run any initialization code for the chapter splitter
send(chapter_type+"_init")

lines.size.times do
  current = lines.delete_at(0)

  if current.nil? or current.size == 0
    chapterlines[chapter_line_num] = current
    current = nil
    chapter_line_num += 1
    next
  end

  # Control codes
  if control? current
    control! current
    next
  end

  # Minimum chapter size (no minimum limit for first chapter/header info)
  if $auto_split and ( chapter_line_num > 5 or chapternum == 0 )
    # Chapter (Boundary) Detection
    new_chapter_title = do_chapter_detection(current,lines,chapter_type)
    boundary = !(new_chapter_title.nil?)
  end

  if boundary or (not $size_limit.nil? and chapter_line_num >= $size_limit)
    boundary = false

    save_chapter(outputname,chapternum,chapter_title,chapterlines)

    chapternum += 1
    chapterlines = {}
    chapterfile = nil
    chapter_line_num = 0
    chapter_title = new_chapter_title
  else
    print "."
    chapterlines[chapter_line_num] = current
  end
  current = nil
  chapter_line_num += 1
end

save_chapter(outputname,chapternum,chapter_title,chapterlines)
