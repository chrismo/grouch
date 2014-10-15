# grouch

Grouch is a brute-force, sloppy `~/.Trash/.DS_Store` parser, to discover
original locations for deleted files/folders, and assist in recovering
a dismembered folder structure properly.

## Background

It was my fault.

I'd gotten a new laptop and in the process of cleaning up the old one
didn't properly de-activate the Google Drive client before cleaning up
a bunch of disk space by removing the local Google Drive folder contents.

The client dutifully began removing all of the files from Google Drive as
as well.

When the mistake was discovered a few days later, recovery of all of the 
files via Google Drive began, but ... it came up short. I don't know why,
I still would like to investigate how the hell Google Drive's own Trash
folder was apparently woefully inadequate[1]. Maybe half of several years
worth of photos and videos were gone from online-land.

The good news is I had my own local backups, and the (hopefully) good 
news is the Google Drive clients on other machines made sure to deposit
the now deleted-from-Google-Drive files into the local Recycle Bin 
(Windows) and Trash (Mac) folders.

Except ... one section of the folder hierarchy had *not* been backed up
locally ... and those files now lived entirely within the Mac Trash 
folder. In addition, to be thorough, I really wanted to restore the 
entirety of the Google Drive hierarchy, to compare with local backups 
just to make sure.

But, maybe because Google Drive was deleting these files and folders 
piecemeal due to sync commands from the hive brain, the Trash folder 
wsa a disaster. Not a single top-level folder to simply Put Back, but
a mishmash of files and dirs, all files named IMG* or VID* and crap.

Put Back didn't work in many cases because (best I can guess):

- If you select a group of files with different original locations
  it won't offer you the Put Back context menu option.

- If you select a file or group going to same original location, you
  can select the Put Back context menu option, but then nothing 
  happens _if_ the original location doesn't exist.

After Googling around a bunch, while I found some RubyCocoa code to
put things into or empty the Trash folder [here](https://github.com/semaperepelitsa/osx-trash/), 
there was no indication that one could programmatically trigger the
Put Back behavior. (If you find anything, please let me know).

I did come across some information stating the `.DS_Store` file 
in the `~/.Trash` folder was where the original location lived, but
nothing on how to obtain it from there. 

Then I found some general information on reverse-engineering of the
`.DS_Store` file [here](http://search.cpan.org/~wiml/Mac-Finder-DSStore/DSStoreFormat.pod),
there was nothing specific to the data I was finding in the Trash
version.

So I started hacking, and the source code here is the result.

It's ugly because, as the comment explains, when most people were 
studying how to do things like this properly in school, I was 
studying jazz, but it helped me Put Back the vast majority of my
disaster, and now I'm sharing it with y'all.





[1] This folder hierarchy was shared by four accounts with mixed ownership
and all over a period of months, I don't know if that contributed to the 
problem. But still - I'm not trusting Google Drive for a while.
