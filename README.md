This is a hacky solution to rename, move and archive video files.

In more detail, onlinetvrecorder.com sends a video to my FTP server. The FTP server stores the file. Upon finalization, incrond calls this script, uploadwatch.sh.

Uploadwatch.sh then parses the file name and the file itself, creates preview images, moves the file according to its extension and stores it into a database.

