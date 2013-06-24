A Modern Perl script to merge two CSV files into a new, third file.

Creating a new file preserves the original data, which is always a good
insurance policy. A log file is created upon each run, detailing the field and
the data gap which was filled. Not found data is not mentioned, only positive
matches are.


Why
---

I needed to fill in gaps in user demographics from legacy data formats. I
converted them into CSV and wrote this Perl script to automate this; The base
CSV file had over 11,000 users.


Future Directions
-----------------

To update an existing CSV file in place, using Tie::CSV could be a decent choice.
