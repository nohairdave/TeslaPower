# The folder where you want to store working files from the script, the defaul is the current folder
mySettings_working_folder=$(pwd .)

# The thresholds you want to apply for super-off-peak, off-peak, mid-peak rates.   These are in pence/kWh.  Peak rate is calculated by the script and unit price data. 
mySettings_super_off_peak_threshold=0
mySettings_off_peak_threshold=15
mySettings_mid_peak_threshold=22

# You can find your site name the first time you run ./testlapower.sh, if you do not know it.  Find "site_name" in products.json located in the working folder
mySettings_site_name="MyPlace"

# Determines the type of meter you have, either E-1R (single rate) or E-2R (dual rate/ecomony 7).  If you are not sure, check your latest Octopus bill and see how many import electric meters you have.
mySettings_meter_type="E-1R"

# You can find your tariff from your latest Octopus bill.  For the code below, use https://api.octopus.energy/v1/products/ to list the available tariffs, then use the one that matches your tariff name.
# For example, if your tariff is "Octopus Agile Oct 2024 v1", then the tariff code is "AGILE-24-10-01"
mySettings_tariff="AGILE-24-10-01"

# You can find your region code from your MPAN number, or assume it by the region you are in - see https://en.wikipedia.org/wiki/Meter_Point_Administration_Number#Distributor_ID
mySettings_region="F"