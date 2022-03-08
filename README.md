# sample_code
sample of report generating code for swimming optimization

The NCHSAA is one of two memmber associations in North Carolina of the National Federation of High Schools (an NGB of sorts for High School Competitions in the US).  I serve as an advisor and vendor for Swimming and Diving.  I run a site that is the clearinghouse for all high school meet results and the entry portal for post-season competition.  As such, I have the data for all results by all swimmers in all events from all schools for the entire season.

Each year, we the advisory board is tasked with setting post-season qualifying times with the general purpose of filling each event with 24 competitors at the regional meets.

Each year, at least one region has an event with fewer than 24 entrants.

Each year, we make the qualifying time slower in order to increase the number of entrants.  

I wished to use the data to determine if slowing the qualifying time down would yield the desired results.

We first looked for a "non-filled" event (that is an event with fewer than 24 entrants).  In this case, Region 9, Event 6 had only 14 entrants.  

We next looked to see how many swimmers had posted post-season qualifying times in that event and region: 32.

So why only 14 entries?

The first thing we notice is that one particular school accounted for 5 of those 32 qualifying times.  Since each school is only allowed 4 entries per event, we know that at least 1 of those 32 will not be entered.  

Can we arrive at an assertion for how coaches will decide whom to enter?

----

Start with the list of best times for each athlete for a given team.
Transcode those times into integer values that reflect the relative strength of those times in a more-or-less equivalent way across events.
Assert that the entry selections that create the greatest sum of those values is the optimum entry lineup for a given team.
Employ constrained linear optimization to determine that such lineup.
Repeat for all teams
Tally up the optimal entries per region per event that meet the qualifying time.

In conclusion, for Region 9, Event 6, it would not matter how much slower the qualifying time was, only 12 entries would be expected.  
