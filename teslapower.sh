#!/bin/bash

# This script fetches the latest Octopus Agile energy rates and updates the time of use settings on a Telsa Powerwall Gateway accordingly, using the free Tesla Owner API.



# Initialise script and environment 

set -u #ensure that unset variables cause an error
set -e #ensure that any command that fails causes the script to exit immediately

## Get my settings for use in the script

source ./mySettings.sh

## Go to working folder and clear out files that will be created by this script

cd $mySettings_working_folder || exit 1
rm -f agile_rates.json
rm -f parsed_agile_rates.txt
rm -f parsed_agile_rates_with_tariff.txt
rm -f parsed_agile_rates_with_tariff_final.txt
rm -f time_of_use_settings.json
rm -f time_of_use_settings_hacked.txt
rm -f tariff_rates_downloaded.json
rm -f tariff_rates_uploaded.json
rm -f parsed_agile_rates_today.txt
rm -f parsed_agile_rates_tomorrow.txt



# Download the latest rates from Octopus Agile

## We need a date range to query the Octopus API,  The Octopus API works on UTC so we need to adjust our start and end based on whether we're on BST or GMT.  We also need to know how to adjust the hour offset for the start and end times when we communicate with the Tesla API.

if [ "$(date +%Z)" = "BST" ]; then
  start_date=$(date -u -j -f "%Y-%m-%d" "$(date -u -v-26H +"%Y-%m-%d")" +"%Y-%m-%dT22:00Z")
  end_date=$(date -u -j -f "%Y-%m-%d" "$(date -u -v+22H +"%Y-%m-%d")" +"%Y-%m-%dT22:00Z")
  offset=1
else
  start_date=$(date -u -j -f "%Y-%m-%d" "$(date -u -v-1H +"%Y-%m-%d")" +"%Y-%m-%dT23:00Z")
  end_date=$(date -u -j -f "%Y-%m-%d" "$(date -u -v+23H +"%Y-%m-%d")" +"%Y-%m-%dT23:00Z")
  offset=0
fi

## Output the start and end dates and the offset

echo "Fetching rates from Octopus Agile for the period from $start_date to $end_date"
echo "Offset time for Tesla API calls by: $offset hour(s)"

## Fetch the rates from the Octopus Agile API

curl "https://api.octopus.energy/v1/products/${mySettings_tariff}/electricity-tariffs/${mySettings_meter_type}-${mySettings_tariff}-${mySettings_region}/standard-unit-rates/?period_from=${start_date}&period_to=${end_date}" >agile_rates.json



# Simplify the Octopus Agile rates to a more manageable and condensed format for loading into the Telsa Powerwall Gateway

## Parse the JSON to get a row for each valid_from, valid_to with associated value_inc_vat into a sorted list

jq -r '.results[] | "\(.valid_from) \(.valid_to) \(.value_inc_vat)"' agile_rates.json | sort > parsed_agile_rates.txt 

## Get min, avg and max for first 48 periods and second 48 periods separately (i.e. today and tomorrow)

periods=$(wc -l < parsed_agile_rates.txt)

cat parsed_agile_rates.txt | head -n 48 > parsed_agile_rates_today.txt
cat parsed_agile_rates.txt | tail -n +49 > parsed_agile_rates_tomorrow.txt

todays_max_value=$(awk '{print $3}' parsed_agile_rates_today.txt | sort -n | tail -n 1)
todays_avg_value=$(awk '{sum += $3; count++} END {if (count > 0) print sum / count; else print 0}' parsed_agile_rates_today.txt)
todays_min_value=$(awk '{print $3}' parsed_agile_rates_today.txt | sort -n | head -n 1)

if [ "$periods" -gt 48 ]; then
  tomorrows_min_value=$(awk '{print $3}' parsed_agile_rates_tomorrow.txt | sort -n | head -n 1)
  tomorrows_avg_value=$(awk '{sum += $3; count++} END {if (count > 0) print sum / count; else print 0}' parsed_agile_rates_tomorrow.txt)
  tomorrows_max_value=$(awk '{print $3}' parsed_agile_rates_tomorrow.txt | sort -n | tail -n 1)
else
  tomorrows_min_value=$todays_min_value
  tomorrows_avg_value=$todays_avg_value
  tomorrows_max_value=$todays_max_value
  echo "Tomorrow's data isnt available, defaulting tomorrow to equal today, re-run this script later (after 4pm)"
fi

## Set the super off-peak, off-peak, mid-peak and peak values based on the thresholds defined in mySettings.sh and max_value

super_off_peak=$mySettings_super_off_peak_threshold
off_peak=$mySettings_off_peak_threshold
mid_peak=$mySettings_mid_peak_threshold

## Set peak values for today and tomorrow based on their respective max values, force peak to be higher than mid rates

peak_today=$todays_max_value
peak_tomorrow=$tomorrows_max_value

if awk "BEGIN {exit !($peak_today <= $mid_peak)}"; then
  peak_today=$(awk "BEGIN {print $mid_peak + 1}")
fi

if awk "BEGIN {exit !($peak_tomorrow <= $mid_peak)}"; then
  peak_tomorrow=$(awk "BEGIN {print $mid_peak + 1}")
fi

peak_today=$(printf "%.4f" "$(echo "$peak_today / 100" | bc -l)")
peak_tomorrow=$(printf "%.4f" "$(echo "$peak_tomorrow / 100" | bc -l)")

## Output the rates and range of values for debugging

echo "Super Off-Peak: $super_off_peak"
echo "Off-Peak: $off_peak"
echo "Mid-Peak: $mid_peak"
echo "Today's Minimum: $todays_min_value"
echo "Today's Average: $todays_avg_value"
echo "Today's Peak: $todays_max_value"
echo "Tomorrow's Minimum: $tomorrows_min_value"
echo "Tomorrow's Average: $tomorrows_avg_value"
echo "Tomorrow's Peak: $tomorrows_max_value"

## Read each line of parsed_agile_rates.txt and assess which tariff it belongs to based on the value_inc_vat and the values in super_off_peak, off_peak, mid_peak, peak.

jq -r --arg super_off_peak "$super_off_peak" \
    --arg off_peak "$off_peak" \
    --arg mid_peak "$mid_peak" \
    '.results[] as $v |
    if ($v.value_inc_vat <= ($super_off_peak | tonumber)) then
      "\($v.valid_from) \($v.valid_to) SUPER_OFF_PEAK"
    elif ($v.value_inc_vat <= ($off_peak | tonumber)) then
      "\($v.valid_from) \($v.valid_to) OFF_PEAK"
    elif ($v.value_inc_vat <= ($mid_peak | tonumber)) then
      "\($v.valid_from) \($v.valid_to) MID_PEAK"
    else
      "\($v.valid_from) \($v.valid_to) ON_PEAK"
    end' agile_rates.json | sort > parsed_agile_rates_with_tariff.txt


## Split this file into the first 48 half hourly periods (today) and the rest (tomorrow)
cat parsed_agile_rates_with_tariff.txt | head -n +48 > parsed_agile_rates_with_tariff_today.txt
cat parsed_agile_rates_with_tariff.txt | tail -n +49 > parsed_agile_rates_with_tariff_tomorrow.txt

## For each file (today and tomorrow)...
for file in parsed_agile_rates_with_tariff_today.txt parsed_agile_rates_with_tariff_tomorrow.txt; do

### if file is empty, skip it
  if [ ! -s "$file" ]; then
    echo "File $file is empty, skipping..."
    echo "periods: $periods"
    continue
  else
    echo "Processing file: $file"
  fi

### Group the data so we have one entry for each tariff change with the earliest start time and latest end time

awk 'BEGIN {current_tariff = ""; current_start = ""; current_end = ""}
{
  if ($3 != current_tariff) {
    if (current_tariff != "") {
      print current_start, current_end, current_tariff
    }
    current_tariff = $3
    current_start = $1
    current_end = $2
  } else {
    current_end = $2
  }
}
END {
  if (current_tariff != "") {
    print current_start, current_end, current_tariff
  }
}' $file > $file.tmp

## Sort the final output by start time and tariff type so we can use it to generate the time_of_use_settings.json file

sort -k3,3 -k1,1 $file.tmp -o $file

## Generate PERIODS for time_of_use_settings from parsed_agile_rates_with_tariff_final.txt
echo "Generating periods for $file"

periods=""
lasttariff=""
comma=""
while read -r line; do
  start=$(echo "$line" | awk '{print $1}')
  end=$(echo "$line" | awk '{print $2}')
  tariff=$(echo "$line" | awk '{print $3}')
  if [ "$tariff" != "$lasttariff" ]; then
    if [ -n "$lasttariff" ]; then
      periods="${periods}\n               ],\n"
    fi
    lasttariff="$tariff"
    periods="$periods               \"$lasttariff\": ["
    comma=""
  fi  

  start_hour=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start" +"%H")
  start_hour=$(( (10#$start_hour + offset) % 24 ))
  start_minute=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start" +%M | sed 's/^0\([0-9]\)/\1/')
  end_hour=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end" +"%H")
  end_hour=$(( (10#$end_hour + offset) % 24 ))
  end_minute=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end" +%M | sed 's/^0\([0-9]\)/\1/')

  periods="$periods$comma\n                 { \"fromDayOfWeek\": 0, \"toHour\": $end_hour, \"toDayOfWeek\": 6, \"fromHour\": $start_hour, \"fromMinute\": $start_minute, \"toMinute\": $end_minute }"
  comma=","
done < $file 

periods="${periods}\n               ]"

### if todaysperiods is not set, set it to periods, otherwise append to it
if [ -z "${todaysperiods+x}" ]; then
  todaysperiods="$periods"
  echo "Today's periods set to: $todaysperiods"
fi

done

## Set the super_off_peak, off_peak, mid_peak and peak values to 4 decimal places for use in the time_of_use_settings.json file

super_off_peak=$(printf "%.4f" "$(echo "$super_off_peak / 100" | bc -l)")
off_peak=$(printf "%.4f" "$(echo "$off_peak / 100" | bc -l)")
mid_peak=$(printf "%.4f" "$(echo "$mid_peak / 100" | bc -l)")
peak=$(printf "%.4f" "$(echo "$peak / 100" | bc -l)")

### Get today's and tomorrow's month and day for use in the time_of_use_settings.json file
todayMonth=$(date +%m | sed 's/^0//')
todayDay=$(date +%d | sed 's/^0//')
tomorrowMonth=$(date -j -v+1d +%m | sed 's/^0//')
tomorrowDay=$(date -j -v+1d +%d | sed 's/^0//')


## Copy time_of_use_settings.template time_of_use_settings.json replacing tariff rates with the values from super_off_peak, off_peak, mid_peak, peak and replacing $PERIODS with the periods generated above

sed -e "s/\$SUPER_OFF_PEAK/$super_off_peak/g" \
    -e "s/\$OFF_PEAK/$off_peak/g" \
    -e "s/\$MID_PEAK/$mid_peak/g" \
    -e "s/\$TODAY_PEAK/$peak_today/g" \
    -e "s/\$TOMORROW_PEAK/$peak_tomorrow/g" \
    -e "s/\$PERIODS/$periods/g" \
    -e "s/\$TODAYS_PERIODS/$todaysperiods/g" \
    -e "s/\$TODAY_MONTH/$todayMonth/g" \
    -e "s/\$TODAY_DAY/$todayDay/g" \
    -e "s/\$TOMORROW_MONTH/$tomorrowMonth/g" \
    -e "s/\$TOMORROW_DAY/$tomorrowDay/g" \
    time_of_use_settings.template > time_of_use_settings.json

## time_of_use_settings.json is now ready to be uploaded to the Tesla Powerwall Gateway

# Upload time_of_use_settings.json to the Tesla Powerwall Gateway

## If the tesla_refresh_token.txt file exists, use it to refresh the token, otherwise prompt the user to login to Tesla to obtain the bearer and access token

if [ ! -f tesla_refresh_token.txt ]; then
  echo "Please login to Tesla to obtain the bearer and access token."
  echo "Visit https://www.myteslamate.com/tesla-token/#instructions and follow the instructions to obtain your access and refresh token."
  read -p "Enter the access token: " access_token
  read -p "Enter the refresh token: " refresh_token
  echo "$refresh_token" > tesla_refresh_token.txt
  echo "$access_token" > tesla_token.txt
  echo "Tokens saved. Continuing..."
else
  refreshToken="$(cat tesla_refresh_token.txt)"

  curl -X POST "https://auth.tesla.com/oauth2/v3/token" \
    -H "Content-Type: application/json" \
    -d '{
          "grant_type": "refresh_token",
      "client_id": "ownerapi",
      "refresh_token": "'"$refreshToken"'"
    }' | jq -r '.access_token' > tesla_token.txt
 
fi

## Get the bearer token from tesla_token.txt

bearer=$(cat tesla_token.txt)

## Fetch the site ID for my site 

curl -X GET "https://owner-api.teslamotors.com/api/1/products" \
  -H "Authorization: Bearer ${bearer}" \
  > products.json 

site_id=$(jq -r --arg name "${mySettings_site_name}" '.response[] | select(.site_name == $name) | .energy_site_id' products.json)

if [ -z "$site_id" ]; then
  echo "Site ID not found for ${mySettings_site_name}"
  exit 1
fi
echo "Site ID for ${mySettings_site_name}: $site_id"

echo "Getting live status..."

curl -X GET "https://owner-api.teslamotors.com/api/1/energy_sites/${site_id}/live_status" \
  -H "Authorization: Bearer ${bearer}"

echo "Getting backup time remaining..."

curl -X GET "https://owner-api.teslamotors.com/api/1/energy_sites/${site_id}/backup_time_remaining" \
  -H "Authorization: Bearer ${bearer}"

echo "Getting current tariff info..."

curl -X GET "https://owner-api.teslamotors.com/api/1/energy_sites/${site_id}/tariff_rate" \
  -H "Authorization: Bearer ${bearer}" \
  >tariff_rates_downloaded.json

echo "Updating tariff info..."

curl -X POST "https://owner-api.teslamotors.com/api/1/energy_sites/${site_id}/time_of_use_settings" \
  -H "Authorization: Bearer ${bearer}" \
  -H "Content-Type: application/json" \
  --data @time_of_use_settings.json

echo "Getting current tariff info..."

curl -X GET "https://owner-api.teslamotors.com/api/1/energy_sites/${site_id}/tariff_rate" \
  -H "Authorization: Bearer ${bearer}" \
  >tariff_rates_uploaded.json
