# lua-carnet-client
LUA script that emulates a VW CarNet browser client

With this script you can communicate with your CarNet connected VW. A CarNet subscription is required.

Enter your user ID and password in the script.

Command line commands supported are:

	startCharge 
	
	stopCharge 
	
	startClimat
	
	stopClimat
	
	startWindowMelt
	
	stopWindowMelt
	
	getNewMessages
	
	getLocation
	
	getVehicleDetails
	
	getVsr
	
	getRequestVsr
	
	getFullyLoadedCars
	
	getNotifications
	
	getTripStatistics
	


Next up will be a plugin for openLuup. I would like to try on a Vera, but it I only got it working wiht luasec 0.7 installed on my PI with Debian. It has to do with either the TSL protocol and/or SNI support. If anyone knows how to work a round this and get it working with luasec 0.5 please let me know.

Have fun
