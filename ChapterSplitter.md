# Introduction #

The chapter splitter script (split.rb) provides a simple, extensible method for splitting ebooks by chapter, particularly for the iPhone's Books.app. Provided an input text file and chapter splitting method, it will output a separate text file for each chapter.


# Configuration #

The script receives its configuration by one of two ways:
  * Command line arguments
  * External configuration file

## Command Line ##

`ruby split.rb inputfile.txt [split method]`

## Config File ##

split.yaml -- Must be in same directory as split.rb
(see the copy of this in subversion for the most up-to-date options)

```
input:
  filename: <input text file>
            example: Lord of the Rings - Book 1.txt
  split method: regex(<option>+<option>+<option>),<title mode>
            example: regex(chapter+number+separator),oneline
            example chapter: Chapter 1: An Unexpected Visitor
            Possible regex options: chapter,roman,arabic,number,
                                    separator,manual,titlecase
            Possible title modes: notitle,oneline,twoline
  split method: <filename containing list of chapters>
  split method: <number of lines per chapter>
            example: 600   causes a new chapter every 600 lines
output:
  name: <output filename>
            example: LotR     yields   001 - LotR.txt
            example: bookname yields   001 - Lord of the Rings - Book 1.txt
            example: chaptertitle yields 001 - An Unexpected Visitor.txt
  name: code(<expression to generate file name>)
            example: code(chapter_title)   yields   001 - An Unexpected Visitor.txt

            Note: for output names, the only user-modifiable part of the name
                  is AFTER the '### - ' (the first part specifies the chapter number
                  and keeps all your chapter files in order
```



# Configuration Options #

Input files should be standard Unicode text files. I haven't done extensive testing of languages other than English, and the regular expressions aren't tuned for anything else, but if Ruby supports reading and writing in a certain format, you should be able to use it with this script.

Chapter splitting is done in one of three ways:
  * Regular expressions (see the section below)
  * Provided list of chapter titles - specify a text file containing one chapter title per line
  * Line count - specify exactly how many lines should be in each chapter file
One of these options should be the first argument after `split method: ` in the configuration file

Additionally, the chapter title's location can be specified in 3 ways (only for regular expressions):
  * No title - `notitle`
  * Same line - `oneline` The part of the line matched by the chapter expression is removed and the remainder of the line is assumed to be the chapter title. If this modified string is empty, the full line is used instead.
  * Next line - `twoline` The line after the chapter boundary is assumed to be the chapter title. If the next line is empty, the boundary line is used instead.
One of these options should follow the regular expression, separated from the expression by a comma (so, `split method: regex(chapter+number+separator),oneline`)

Finally, the output file's names can be specified in several ways:
  * Exact string - `name: LotR-Book 1` results in **001 - LotR-Book 1.txt**
  * Book name - `name: book name` results in **001 - Book 1.txt** (input file was **Book 1.txt**)
  * Chapter name `name: chapter title` results in **001 - An Unexpected Party.txt**
  * Custom expression - `name: "LotR "+chapter_title` results in **001 - LotR An Unexpected Party.txt**

## Regular Expressions ##

This is the most common way to split a book. Regular expressions are defined at the beginning of the script as global variables (begin with a $). To specify the regular expressions you would like to use for a given book, you just list the variables containing the regular expressions (without the $) separated by plus (+) signs. So, to detect chapter titles in the _Chapter 1: An Unexpected Party_ format, you would specify `regex(chapter+number+separator)`. This tells the splitter to look for the word Chapter followed by one or more numbers, and finally a separation character. The full list of variables and examples of matches follows.


### chapter ###
Chapter or CHAPTER
must be followed by a space

### roman ###
A roman numeral between 1 and 4999 (I to MMMMCMXCIX)
An empty string is also a match, so `regex(chapter+roman)` applied to _Chapter Under Review_ would result in a match.

### number ###
Also `arabic`. A number between 0 and 999. Does not match an empty string.

### separator ###
Any _one_ of the following characters:
```
. (period)
: (colon)
  (space)
- (hyphen or dash, _not_ em-dash)
_ (underscore)
```

### manual ###
The exact string **CHAPTERBOUNDARY**. Used for manual tagging of chapters

### titlecase ###
Every word must begin with a capitol letter and the line cannot end with punctuation. Also, there must be no more than 10 words on the line. Does not match an empty string.
|Example: An Unexpected Party|
|:---------------------------|
|Exception: The following words may be lower case: `a|an|and|at|by|for|from|in|of|or|the|to`|