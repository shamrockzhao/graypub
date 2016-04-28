local redisLib = require "resty.redis"
local cookieLib = require "resty.cookie"
local json = require("json")

local redis = redisLib:new()
if not redis then
    ngx.log(ngx.ERR, err)
    ngx.exec("@defaultProxy")
end

local cookie, err = cookieLib:new()
if not cookie then
    ngx.log(ngx.ERR, err)
    return "@defaultProxy"
end

-- set cookie(模拟测试) 
--[[
local ok, err = cookie:set({
    key = "uid", value = "100",
})
if not ok then
    ngx.log(ngx.ERR, err)
    ngx.exec("@defaultProxy")
end
]]

-- get cookie
local uid, err = cookie:get("uid")
if not uid then
    ngx.log(ngx.ERR, err)
    ngx.exec("@defaultProxy")
end

redis:set_timeout(1000)
local ok, err = redis:connect('127.0.0.1', '6379')
if not ok then
    ngx.log("failed to connect:", err)
    ngx.exec("@defaultProxy")
end

-- 根据用户会话ID获取用户属性
-- 也可以直接通过后端应用set到cookie然后在这里解析即可, 少一次redis调用
-- eg: {'tag1':'2','tag2':'1','tag3':'0'}
local tags, err = redis:get(uid)
if not tags then
        ngx.log("failed to get uid: ", err)
        ngx.exec("@defaultProxy")
end

if tags == ngx.null then
    ngx.log("uid not found.")
    ngx.exec("@defaultProxy")
end

-- 获取规则配置信息, 需要做一定的缓存策略
-- eg: {'tag':'tag1','proxy':{'0':'proxy_a','1':'proxy_a','2':'proxy_b'}}
local proxyConfig, err = redis:get("proxyConfig")
if not proxyConfig then
        ngx.log("failed to get proxyConfig: ", err)
        ngx.exec("@defaultProxy")
end

if proxyConfig == ngx.null then
    ngx.log("proxyConfig not found.")
    ngx.exec("@defaultProxy")
end

-- put it into the connection pool of size 100,
-- with 10 seconds max idle time
local ok, err = red:set_keepalive(10000, 100)
if not ok then
    ngx.say("failed to set keepalive: ", err)
    return
end


proxyConfigData = json.decode(proxyConfig)
tagsData = json.decode(tags)
tag = proxyConfigData.tag

-- 解析规则处理
-- 根据规则里配置的类型和用户标签做匹配, 分流到相应的服务器上
-- 这里是可以按照用户标签维度支持比较灵活的配置分流规则, 如果业务逻辑简单的话也可以简化
proxy = "@defaultProxy"
for k_tag, v_tag in pairs(tagsData) do
        if k_tag == tag then
                for k_proxy, v_proxy in pairs(proxyConfigData.proxy) do
                        if v_tag == k_proxy then
                                proxy = v_proxy
                                break
                        end
                end
        end
end

ngx.exec(proxy)