# Set Tesla Powerwall Gateway rates base on Octopus rates

This is a very simple script that aims to update your Tesla Powerwall Gateway with tariff updates from Octopus.  It is written specifically for MacOSX (I'm running version 15.6) with no pre-requsites.  Hopefully others can contribute to this version to make it platform agnostic.  I've based this on snippets of information I've found trawling the internet, I havent captured all sources here but will do when I get time to trawl through by browsing history. 

The script should be run daily after 4pm to pick up Octopus's daily rate updates.

Why write this?  Well, for two reasons: 

1/ the most important - fun

2/ to avoid subscribing to NetZero following their change in fees from 1st August 2025

My aim isnt to replace the full functionality of NetZero, but just to use the Tesla's Owner's API (free to use) to update half-hourly tariff rates to make the Tesla Powerwall take advantage of low price energy.   

I've taken a slightly different approach to other people who have coded some beautiful graphics to visualise rates and other data from the gateway - this is focused solely on getting pricing data into the Tesla Powerwall Gateway.

I've simpllified rates during the update process.  You can set a super-off-peak, off-peak and mid-peak threshold you want to apply to the tariffs.  This seems to get the The reality is that the tesla app wont retain previous pricing data once the script is run, so the focus is on today's and tomorrow's rates.

Authorisation is a hack at the moment (follow the instrunctions from the script on first run).  Ideally this could be automated.

If you dont know the name of your site, when you run the script for the first time, see the products.json file for a list of your tesla products, and customise mySettings.sh to reflect the name of your site.

I've been lazy with solar export tariffs - just fixed it to 15p/kw as thats my tariff.  Theoretically, the same principles I've used to obtain export pricing could be used, but this needs coding.


