--[[
# Script to emulate VW CarNet web site
# Author  : Rene Boer
# Version : 1.0
# Date    : 5 Jan 2018
# Free for use & distribution
]]
local url 		= require("socket.url")
local socket 	= require("socket")
local http 		= require("socket.http")
local ltn12 	= require("ltn12")
local json 		= require("json")
local https     = require "ssl.https"

local CARNET_USERNAME = 'rene@reneboer.demon.nl'
local CARNET_PASSWORD = '[5yWuwy?.p6H'

local port_host = "www.volkswagen-car-net.com"
local HEADERS = { 
	['Accept'] = 'application/json, text/plain, */*',
	['Content-Type'] = 'application/json;charset=UTF-8',
	['User-Agent'] = 'Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:57.0) Gecko/20100101 Firefox/57.0' 
}

-- Map commands to details
local commands = {
	['startCharge'] = { url ='/-/emanager/charge-battery', json = '{ "triggerAction" : true, "batteryPercent" : 100 }' },
	['stopCharge'] = { url ='/-/emanager/charge-battery', json = '{ "triggerAction" : false, "batteryPercent" : 99 }' },
	['startClimat'] = { url ='/-/emanager/trigger-climatisation', json = '{ "triggerAction" : true, "electricClima" : true }' },
	['stopClimat'] = { url ='/-/emanager/trigger-climatisation', json = '{ "triggerAction" : false, "electricClima" : true }' },
	['startWindowMelt'] = { url ='/-/emanager/trigger-windowheating', json = '{ "triggerAction" : true }' },
	['stopWindowMelt'] = {url ='/-/emanager/trigger-windowheating', json = '{ "triggerAction" : false }' },
	['getNewMessages'] = {url ='/-/msgc/get-new-messages' },
	['getLocation'] = {url ='/-/cf/get-location' },
	['getVehicleDetails'] = {url ='/-/vehicle-info/get-vehicle-details' },
	['getVsr'] = {url ='/-/vsr/get-vsr' },
	['getRequestVsr'] = {url ='/-/vsr/request-vsr' },
	['getFullyLoadedCars'] = {url ='/-/mainnavigation/get-fully-loaded-cars' },
	['getNotifications'] = {url ='/-/emanager/get-notifications' },
	['getTripStatistics'] = {url ='/-/rts/get-latest-trip-statistics' }
}

local function sleep(secs)
	socket.sleep(secs)
end

local function _postencodepart(s)
	return s and (s:gsub("%W", function (c)
		if c ~= "." and c ~= "_" then
			return string.format("%%%02X", c:byte());
		else
			return c;
		end
	end));
end

local function postencode(p_data)
	local result = {};
	if p_data[1] then -- Array of ordered { name, value }
		for _, field in ipairs(p_data) do
			table.insert(result, _postencodepart(field[1]).."=".._postencodepart(field[2]));
		end
	else -- Unordered map of name -> value
		for name, value in pairs(p_data) do
			table.insert(result, _postencodepart(name).."=".._postencodepart(value));
		end
	end
	return table.concat(result, "&");
end

-- HTTP Get request
local function HttpsGet(strURL,ReqHdrs)
	local result = {}
--[[print('request')
print('GET '..strURL)
print('headers')
for k,v in pairs(ReqHdrs) do
	print ('    hdr '..k.. " : ".. (v or ''))		
end
]]
	local bdy,cde,hdrs,stts = https.request{
		url=strURL, 
		method='GET',
		sink=ltn12.sink.table(result),
		redirect = false,
		headers = ReqHdrs
	}
--[[print('status : '..cde)
print('headers')
for k,v in pairs(hdrs) do
	print ('   '..k.. " : ".. (v or ''))		
end
print('')
]]
	return bdy,cde,hdrs,result
end	

-- HTTP POST request
local function HttpsPost(strURL,ReqHdrs,PostData)
	local result = {}
	local request_body = nil
--print('request')
--print('POST '..strURL)
	if PostData then
		-- We pass JSONs as string as they are simple in this application
		if type(PostData) == 'string' then
			ReqHdrs["content-type"] = 'application/json;charset=UTF-8'
			request_body=PostData
		else	
			ReqHdrs["content-type"] = 'application/x-www-form-urlencoded'
			request_body=postencode(PostData)
		end
		ReqHdrs["content-length"] = string.len(request_body)
--print('data')	
--print('    '..request_body)	
	else	
		ReqHdrs["content-length"] = '0'
	end  
--[[print('headers')
for k,v in pairs(ReqHdrs) do
	print ('    hdr '..k.. ":".. (v or ''))		
end
]]
	local bdy,cde,hdrs,stts = https.request{
		url=strURL, 
		method='POST',
		sink=ltn12.sink.table(result),
		source = ltn12.source.string(request_body),
		headers = ReqHdrs
	}
--[[print('status : '..cde)
print('headers')
for k,v in pairs(hdrs) do
	print ('   '..k.. " : ".. (v or ''))		
end
print('')
]]
	return bdy,cde,hdrs,result
end	


-- Login routine
local function CarNetLogin(email, password)
	local sec_host = 'security.volkswagen.com'
	local bdy,cde,hdrs,result
	-- Fixed URLs to use in order
	local URLS = { 
		'https://' .. port_host .. '/portal/en_GB/web/guest/home', 
		'https://' .. port_host .. '/portal/en_GB/web/guest/home/-/csrftokenhandling/get-login-url',
		'https://' .. sec_host  .. '/ap-login/jsf/login.jsf',
		'https://' .. port_host .. '/portal/en_GB/web/guest/complete-login', 
		'https://' .. port_host .. '/portal/en_GB/web/guest/complete-login/-/mainnavigation/get-countries' 
	}
	-- Base Headers to start with
	local AUTHHEADERS = {
		['host'] = port_host,
		['accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
		['accept-language'] = 'en-US,en;q=0.5',
		['user-agent'] = 'Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:57.0) Gecko/20100101 Firefox/57.0', 
		['connection'] = 'keep-alive'
	}

	-- Clone header table so we can start over as needed
	local function header_clone(orig)
		local copy
		if type(orig) == 'table' then
			copy = {}
			for orig_key, orig_value in pairs(orig) do
				copy[orig_key] = orig_value
			end
		else -- number, string, boolean, etc
			copy = orig
		end
		return copy
	end
	
	
	-- Request landing page and get CSFR Token:
	local req_hdrs = header_clone(AUTHHEADERS)
	bdy,cde,hdrs,result = HttpsGet(URLS[1],req_hdrs)
	if cde ~= 200 then return '', '1' end
	local cookie_Init = ''
	local cookie_JS = ''
	if (hdrs and hdrs['set-cookie']) then 
		cookie_JS = string.match(hdrs['set-cookie'],'JSESSIONID=([%w%.]+); Path=')
		if cookie_JS then
			cookie_Init = 'JSESSIONID='.. cookie_JS ..'; GUEST_LANGUAGE_ID=en_GB; COOKIE_SUPPORT=true; CARNET_LANGUAGE_ID=en_GB; VW_COOKIE_AGREEMENT=true;'
		end	
	end
	-- Get x-csrf-token from html result
	local csrf = string.match(result[1],'<meta name="_csrf" content="(%w+)"/>')
	if not csrf then return '', '1.1'  end

	-- Get login page
	-- Update header with required info
	req_hdrs['referer'] = URLS[1]
	req_hdrs['x-csrf-token'] = csrf
	req_hdrs['accept'] = 'application/json, text/plain, */*'
	req_hdrs['cookie'] = cookie_Init
	bdy,cde,hdrs,result = HttpsPost(URLS[2],req_hdrs)
	if cde ~= 200 then return '', '2'  end
	local responseData = json.decode(table.concat(result))
	local lg_url = responseData.loginURL.path
	if not lg_url then return '', '2.1'  end
	
	-- Get redirect page, we should not have a redirect
	req_hdrs = header_clone(AUTHHEADERS)
	req_hdrs['referer'] = URLS[1]
	req_hdrs['cookie'] = 'PF=CZXp7A7tbc0Cn6Af6Fu4eP' -- Dummy value
	req_hdrs['host'] = sec_host
	req_hdrs['upgrade-insecure-requests'] = '1'
	-- stops here unless you install luasec 0.7 as SNI is not supported by luasec 0.5 or 0.6. Show stopper for Vera it seems.
	
	bdy,cde,hdrs,result = HttpsGet(lg_url,req_hdrs)
	local cookie_PF = ''
	if (hdrs and hdrs['set-cookie']) then 
		cookie_PF = string.match(hdrs['set-cookie'],'PF=(%w+);')
	end
	if cde ~= 302 then return '', '3'  end
	ref_url = hdrs.location
	if not ref_url then return '', '3.1'  end
	
	-- now get actual login page and get session id and ViewState
	req_hdrs['cookie'] = 'JSESSIONID='.. cookie_JS ..'; PF='..cookie_PF
	bdy,cde,hdrs,result = HttpsGet(ref_url,req_hdrs)
	if cde ~= 200 then return '', '4'  end
	if (hdrs and hdrs['set-cookie']) then 
		cookie_JS = string.match(hdrs['set-cookie'],'JSESSIONID=([%w%.]+); Path=')
	end
	local view_state = string.match(table.concat(result),'name="javax.faces.ViewState" id="j_id1:javax.faces.ViewState:0" value="([%-:0-9]+)"')
	if not view_state then return '', '4.1'  end

	-- Submit login details
	req_hdrs = header_clone(AUTHHEADERS)
	req_hdrs['accept'] = '*/*'
	req_hdrs['faces-request'] = 'partial/ajax'
	req_hdrs['referer'] = ref_url
	req_hdrs['cookie'] = 'JSESSIONID='..cookie_JS .. '; PF='..cookie_PF
	req_hdrs['host'] = sec_host

	local post_data = { 
		{'loginForm', 'loginForm'},
		{'loginForm:email', email},
		{'loginForm:password', password},
		{'loginForm:j_idt19', ''},
		{'javax.faces.ViewState', view_state},
		{'javax.faces.source', 'loginForm:submit'},
		{'javax.faces.partial.event', 'click'},
		{'javax.faces.partial.execute', 'loginForm:submit loginForm'},
		{'javax.faces.partial.render', 'loginForm'},
		{'javax.faces.behavior.event', 'action'},
		{'javax.faces.partial.ajax','true'}
	}
	bdy,cde,hdrs,result = HttpsPost(URLS[3],req_hdrs, post_data)
	if cde ~= 200 then return '', '5'  end
	local cookie_SO = ''
	if (hdrs and hdrs['set-cookie']) then 
		cookie_SO = string.match(hdrs['set-cookie'],'SsoProviderCookie=(.+); Domain=.volkswagen.com;')
	end
	if not cookie_SO then return '', '5.1'  end
	local ref_url1 =string.gsub(string.match(table.concat(result),'<redirect url="([^"]*)"></redirect>'),'&amp;','&')
	if not ref_url1 then return '', '5.2'  end

	req_hdrs = header_clone(AUTHHEADERS)
	req_hdrs['cookie'] = 'PF='..cookie_PF..'; SsoProviderCookie='..cookie_SO
	req_hdrs['referer'] = ref_url
	req_hdrs['host'] = sec_host
	bdy,cde,hdrs,result = HttpsGet(ref_url1,req_hdrs)
	if cde ~= 302 then return '', '6'  end
	local ref_url2 = hdrs.location
	if not ref_url2 then return '', '6.1'  end

	-- Get code and state details
	local code = string.match(ref_url2,'code=([^"]*)&')
	req_hdrs = header_clone(AUTHHEADERS)
	req_hdrs['referer'] = ref_url
	bdy,cde,hdrs,result = HttpsGet(ref_url2,req_hdrs)
	if cde ~= 200 then return '', '7'  end

	-- Get countries, not realy needed.
	req_hdrs = header_clone(AUTHHEADERS)
	req_hdrs['referer'] = ref_url2
	req_hdrs['cookie'] = cookie_Init
	req_hdrs['x-csrf-token'] = csrf
	bdy,cde,hdrs,result = HttpsPost(URLS[5],req_hdrs)
	
	req_hdrs = header_clone(AUTHHEADERS)
	req_hdrs['referer'] = ref_url2
	req_hdrs['cookie'] = cookie_Init
	post_data = { 
		{'_33_WAR_cored5portlet_code', code },
		{'_33_WAR_cored5portlet_landingPageUrl', ''}
	}
	bdy,cde,hdrs,result = HttpsPost(URLS[4].. '?p_auth=' .. csrf .. '&p_p_id=33_WAR_cored5portlet&p_p_lifecycle=1&p_p_state=normal&p_p_mode=view&p_p_col_id=column-1&p_p_col_count=1&_33_WAR_cored5portlet_javax.portlet.action=getLoginStatus',req_hdrs, post_data)
	if cde ~= 302 then return '', '8'  end
	if (hdrs and hdrs['set-cookie']) then 
		cookie_JS = string.match(hdrs['set-cookie'],'JSESSIONID=([%w%.]+); Path=')
	end
	if not cookie_JS then return '', '8.1'  end
	ref_url3 = hdrs.location
	if not ref_url3 then return '', '8.2'  end

	local cookie = 'JSESSIONID='.. cookie_JS ..'; GUEST_LANGUAGE_ID=en_GB; COOKIE_SUPPORT=true; CARNET_LANGUAGE_ID=en_GB;'
	req_hdrs = header_clone(AUTHHEADERS)
	req_hdrs['referer'] = ref_url2
	req_hdrs['cookie'] = cookie
	bdy,cde,hdrs,result = HttpsGet(ref_url3,req_hdrs)
	if cde ~= 200 then return '', '9'  end

	--We have a new CSRF
	csrf = string.match(result[1],'<meta name="_csrf" content="(%w+)"/>')
	-- done!!!! we are in at last
	return ref_url3, csrf, cookie
end


-- Start of main 
local command = arg[1]
if command then print ('arg 1 '..arg[1]) end

-- Login
local url,token,cookie = CarNetLogin(CARNET_USERNAME,CARNET_PASSWORD)
print('portal : '..url)
print('token : '.. token)
if url == '' then
	print("Failed to login")
else
	local bdy,cde,hdrs,result 
	local req_hdrs = HEADERS
	req_hdrs['x-csrf-token'] = token
	req_hdrs['origin'] = 'https://'..port_host
	req_hdrs['referer'] = url
	req_hdrs['cookie'] = cookie

	if not command then
		bdy,cde,hdrs,result = HttpsPost(url..commands['getFullyLoadedCars'].url,req_hdrs)
		print(table.concat(result))
	else
		cm_url = commands[command].url
		cm_data = commands[command].json
		if cm_url then 
			bdy,cde,hdrs,result = HttpsPost(url..cm_url,req_hdrs,cm_data)
			print(table.concat(result))
			local res_js = json.decode(table.concat(result))
			if cm_data and res_js.errorCode == '0' then
				-- Command send, look for response
				local state = 'SUCCEEDED'
				if res_js.actionNotification then 
					state = res_js.actionNotification.actionState
				elseif res_js.actionNotificationList then 
					state = res_js.actionNotificationList[1].actionState
				end	
				if state == 'QUEUED' then
					for cnt = 1, 4 do
						sleep(10)
						bdy,cde,hdrs,result = HttpsPost(url..commands['getNewMessages'].url,req_hdrs)
						print(table.concat(result))
						sleep(10)
						bdy,cde,hdrs,result = HttpsPost(url..commands['getNewMessages'].url,req_hdrs)
						print(table.concat(result))
						sleep(10)
						bdy,cde,hdrs,result = HttpsPost(url..commands['getNewMessages'].url,req_hdrs)
						print(table.concat(result))
						sleep(10)
						bdy,cde,hdrs,result = HttpsPost(url..commands['getNotifications'].url,req_hdrs)
						print(table.concat(result))
						local res_js = json.decode(table.concat(result))
						if res_js.errorCode == '0' then
							if res_js.actionNotification then 
								state = res_js.actionNotification.actionState
							elseif res_js.actionNotificationList then 
								state = res_js.actionNotificationList[1].actionState
							end	
							if state == 'SUCCEEDED' then break end
						end
					end
				end
			end
		end
	end
end

