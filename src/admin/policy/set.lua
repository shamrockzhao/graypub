local policyModule  = require('grayPub.adapter.policy')
local redisModule   = require('grayPub.utils.redis')
local systemConf    = require('grayPub.utils.init')
local handler       = require('grayPub.error.handler').handler
local utils         = require('grayPub.utils.utils')
local ERRORINFO     = require('grayPub.error.errcode').info

local cjson         = require('cjson.safe')
local doresp        = utils.doresp
local dolog         = utils.dolog

local redisConf     = systemConf.redisConf
local divtypes      = systemConf.divtypes
local prefixConf    = systemConf.prefixConf
local policyLib     = prefixConf.policyLibPrefix

local request_body  = ngx.var.request_body
local postData      = cjson.decode(request_body)

if not request_body then
    -- ERRORCODE.PARAMETER_NONE
    local errinfo	 = ERRORINFO.PARAMETER_NONE
    local desc		 = 'request_body or post data'
    local response	 = doresp(errinfo, desc)
    dolog(errinfo, desc)
    ngx.say(response)
    return
end

if not postData then
    -- ERRORCODE.PARAMETER_ERROR
    local errinfo	= ERRORINFO.PARAMETER_ERROR 
    local desc		= 'postData is not a json string'
    local response	= doresp(errinfo, desc)
    dolog(errinfo, desc)
    ngx.say(response)
    return
end

local divtype = postData.divtype
local divdata = postData.divdata

if not divtype or not divdata then
    -- ERRORCODE.PARAMETER_NONE
    local errinfo	= ERRORINFO.PARAMETER_NONE 
    local desc		= "policy divtype or policy divdata"
    local response	= doresp(errinfo, desc)
    dolog(errinfo, desc)
    ngx.say(response)
    return
end

if not divtypes[divtype] then
    -- ERRORCODE.PARAMETER_TYPE_ERROR
    local errinfo	= ERRORINFO.PARAMETER_TYPE_ERROR 
    local desc		= "unsupported divtype"
    local response	= doresp(errinfo, desc)
    dolog(errinfo, desc)
    ngx.say(response)
    return
end

local red = redisModule:new(redisConf)
local ok, err = red:connectdb()
if not ok then
    -- ERRORCODE.REDIS_CONNECT_ERROR
    -- connect to redis error
    local errinfo	= ERRORINFO.REDIS_CONNECT_ERROR
    local response	= doresp(errinfo, err)
    dolog(errinfo, err)
    ngx.say(response)
    return
end

local policyMod
local policy   = postData

local pfunc = function() 
    policyMod = policyModule:new(red.redis, policyLib)
    return policyMod:check(policy)
end

local status, info = xpcall(pfunc, handler)
if not status then
    local errinfo  = info[1]
    local errstack = info[2] 
    local err, desc = errinfo[1], errinfo[2]
    local response	= doresp(err, desc)
    dolog(err, desc, nil, errstack)
    ngx.say(response)
    return
end

local chkout    = info
local valid     = chkout[1]
local err       = chkout[2]
local desc      = chkout[3]

if not valid then
    dolog(err, desc)
    local response = doresp(err, desc)
    ngx.say(response)
    return
end

local pfunc = function() return policyMod:set(policy) end
local status, info = xpcall(pfunc, handler)
if not status then
    local errinfo   = info[1]
    local errstack  = info[2] 
    local err, desc = errinfo[1], errinfo[2]
    local response  = doresp(err, desc)
    dolog(err, desc, nil, errstack)
    ngx.say(response)
    return
end

local data
if info then
    data = ' the id of new policy is '..info
end

local response = doresp(ERRORINFO.SUCCESS, data)
ngx.say(response)
