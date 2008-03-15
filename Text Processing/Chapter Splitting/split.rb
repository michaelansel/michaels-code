#!/usr/bin/ruby

### Regular Expressions
$chapter = "C((hapter)|(HAPTER))[ ]"
$roman = """
M{0,4}              # thousands - 0 to 4 M's
((CM)|(CD)|(D?C{0,3}))    # hundreds - 900 (CM), 400 (CD), 0-300 (0 to 3 C's),
                    #            or 500-800 (D, followed by 0 to 3 C's)
((XC)|(XL)|(L?X{0,3}))    # tens - 90 (XC), 40 (XL), 0-30 (0 to 3 X's),
                    #        or 50-80 (L, followed by 0 to 3 X's)
((IX)|(IV)|(V?I{0,3}))    # ones - 9 (IX), 4 (IV), 0-3 (0 to 3 I's),
                    #        or 5-8 (V, followed by 0 to 3 I's)
"""
$arabic = $number = "[0-9]{1,3}"
$separator = "[.: -_]"
$manual = "CHAPTERBOUNDARY"
$titlecase = """
^\\b
(
  (                   # Begin word
    ([A-Z]\\w*(\\'s)?)  # Word must start with a capitol letter
          |           # or, one of the following special words
    (a|an|and|at|by|for|from|in|of|or|the|to)
  )                   # End word
  \\W*      # Any number of non-word characters between words           
){1,10}    # < 10 words in title
\\b$        # End with a word boundary (no punctuation)
"""



### Chapter title detection methods

def detect_chapters(current,lines,options={})
#  if rules and title
#  if !rulesnil and !titlenil
#  if !(rulesnil or titlenil)
  unless options[:rules].nil? or options[:title_mode].nil?
    regex = /#{eval('a=$'+options[:rules].join('+$'))}/x
    return nil unless current.strip =~ regex
    return send(options[:title_mode],current,lines,regex)
  end
  return check_list(current) unless $chapter_titles[0].nil? or current.nil?
  return nil
end

def notitle(current,lines,regex)
  return ""
end

def oneline(current,lines,regex)
  a = current.strip.sub(regex,'').strip
  return a unless a.length == 0
  return current
end

def twoline(current,lines,regex)
  a = lines.delete_at(0).strip
  return a unless a.length == 0 or a.nil?
  return current
end

def check_list(current)
  return $chapter_titles.delete_at(0) if current.strip =~ /#{$chapter_titles[0].strip}$/ #case sensitive
  return nil
end





### Other Methods

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
  if code.strip =~ /^AUTO-OFF$/
    $auto_split = false
  end
  if code.strip =~ /^AUTO-ON$/
    $auto_split = true
  end
end




### Main code

$DIR = File.dirname(File.expand_path(__FILE__))
abort "usage: split.rb inputfile.txt [chapter type]" if ARGV.size < 1 and not File.exist? $DIR+'/split.yaml'

# Defaults
chapternum = 0
chapter_line_num = 0
chapterlines = {}
chapter_title = "Header Information\n"
split_method = "regex(titlecase),oneline"
outputname = '$inputfile.split(".")[0]'
$auto_split = true


# Command line arguments
$inputfile = ARGV[0] if ARGV.size >= 1
split_method = ARGV[1] if ARGV.size >= 2

# Configuration file
if File.exist? $DIR+'/split.yaml'
  require 'yaml'
  config = YAML.load_file($DIR+"/split.yaml")

  #Input settings
  if config["input"]
    $inputfile = config["input"]["filename"] if config["input"]["filename"]
    split_method = config["input"]["split method"].to_s if config["input"]["split method"]
  end

  #Output settings
  if config["output"]
    outputname = config["output"]["name"] if config["output"]["name"]
  end

end


# Determine the exact splitting method
if split_method =~ /^regex[(].*[)]/i
  rules = split_method.sub(/^regex [(] (\w+ ([+]\w+)*) [)] .*/ix,'\1').split("+")
  title_mode = split_method.sub(/^regex [(] (\w+ ([+]\w+)*) [)] ,/ix,'')
end
$chapter_titles = IO.readlines $DIR+"/"+split_method if split_method =~ /\.txt$/i
$size_limit = split_method.strip.to_i if split_method =~ /[0-9]+/


# Determine exact expression to generate output filename
if outputname =~ /code[(][^)][)]$/i
  outputname = outputname.sub(/^code[(]([^)])[)]$/i,'\1')
elsif outputname =~ /books?.?names?/i
  outputname = '$inputfile.split(".")[0].strip'
elsif outputname =~ /chapters?.?((names?)|(titles?))?/i
  outputname = 'chapter_title.strip'
else
  outputname = '"'+outputname+'".strip'   # Hack to turn a string into an expression
end

# Sanity check
abort "You must specify an input filename and a chapter split type" if $inputfile.nil? or split_method.nil?
# Print out book name
puts $inputfile.split(".")[0]
# Read book into memory
lines = IO.readlines $DIR+'/'+$inputfile
# Sanity check
abort "The book file is empty!" if lines.nil?


# Start processing the book!

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

  # Minimum chapter size (no minimum limit for header info)
  if $auto_split and not $size_limit and ( chapter_line_num > 5 or chapternum == 0 )
    # Chapter (Boundary) Detection
    #new_chapter_title = do_chapter_detection(current,lines,chapter_type)
    new_chapter_title = detect_chapters(current,lines,:rules => rules,:title_mode => title_mode)
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
