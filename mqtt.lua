--
-- mqtt.lua is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- mqtt.lua is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with mqtt.lua.  If not, see <http://www.gnu.org/licenses/>.
--
--
-- Copyright 2012 Vicente Ruiz Rodríguez <vruiz2.0@gmail.com>. All rights reserved.
--

do
	-- Create a new dissector
	print("MQTT-FB dessector inside")
	MQTTPROTO = Proto("MQTT-FB", "Facebook MQTT")
	local bitw = require("bit32")
	local f = MQTTPROTO.fields
	-- Fix header: byte 1
	f.message_type = ProtoField.uint8("mqttfb.message_type", "Message Type", base.HEX, nil, 0xF0)
	f.dup = ProtoField.uint8("mqttfb.dup", "DUP Flag", base.DEC, nil, 0x08)
	f.qos = ProtoField.uint8("mqttfb.qos", "QoS Level", base.DEC, nil, 0x06)
	f.retain = ProtoField.uint8("mqttfb.retain", "Retain", base.DEC, nil, 0x01)
	-- Fix header: byte 2
	f.remain_length = ProtoField.uint8("mqttfb.remain_length", "Remain Length")

	-- Connect
	f.connect_protocol_name = ProtoField.string("mqttfb.connect.protocol_name", "Protocol Name")
	f.connect_protocol_version = ProtoField.uint8("mqttfb.connect.protocol_version", "Protocol Version")
	f.connect_username = ProtoField.uint8("mqttfb.connect.username", "Username Flag", base.DEC, nil, 0x80)
	f.connect_password = ProtoField.uint8("mqttfb.connect.password", "Password Flag", base.DEC, nil, 0x40)
	f.connect_will_retain = ProtoField.uint8("mqttfb.connect.will_retain", "Will Retain Flag", base.DEC, nil, 0x20)
	f.connect_will_qos = ProtoField.uint8("mqttfb.connect.will_qos", "Will QoS Flag", base.DEC, nil, 0x18)
	f.connect_will = ProtoField.uint8("mqttfb.connect.will", "Will Flag", base.DEC, nil, 0x04)
	f.connect_clean_session = ProtoField.uint8("mqttfb.connect.clean_session", "Clean Session Flag", base.DEC, nil, 0x02)
	f.connect_keep_alive = ProtoField.uint16("mqttfb.connect.keep_alive", "Keep Alive (secs)")

	-- Publish
	f.publish_topic = ProtoField.string("mqttfb.topic", "Topic")
	f.publish_message_id = ProtoField.uint16("mqttfb.publish.message_id", "Message ID")

	-- Subscribe
	f.subscribe_message_id = ProtoField.uint16("mqttfb.subscribe.message_id", "Message ID")
	f.subscribe_qos = ProtoField.uint8("mqttfb.subscribe.qos", "QoS")

	-- SubAck
	f.suback_qos = ProtoField.uint8("mqttfb.suback.qos", "QoS")

	-- Suback
	f.suback_message_id = ProtoField.uint16("mqttfb.suback.message_id", "Message ID")
	f.suback_qos = ProtoField.uint8("mqttfb.suback.qos", "QoS")
	--
	f.payload_re_data = ProtoField.bytes("mqttfb.payload.regular", "Payload Regular Data")
	f.payload_data = ProtoField.bytes("mqttfb.payload", "Payload Uncompress Data")

	-- decoding of fixed header remaining length
	-- according to MQTT V3.1
	function lengthDecode(buffer, offset)
		local multiplier = 1
		local value = 0
		local digit = 0
		repeat
			 digit = buffer(offset, 1):uint()
			 offset = offset + 1
			 value = value + bitw.band(digit,127) * multiplier
			 multiplier = multiplier * 128
		until (bitw.band(digit,128) == 0)
		return offset, value
	end

	-- The dissector function
	function MQTTPROTO.dissector(buffer, pinfo, tree)
		pinfo.cols.protocol = "MQTT"
		local msg_types = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }
		msg_types[1] = "CONNECT"
		msg_types[2] = "CONNACK"
		msg_types[3] = "PUBLISH"
		msg_types[4] = "PUBACK"
		msg_types[5] = "PUBREC"
		msg_types[6] = "PUBREL"
		msg_types[7] = "PUBCOMP"
		msg_types[8] = "SUBSCRIBE"
		msg_types[9] = "SUBACK"
		msg_types[10] = "UNSUBSCRIBE"
		msg_types[11] = "UNSUBACK"
		msg_types[12] = "PINGREQ"
		msg_types[13] = "PINGRESP"
		msg_types[14] = "DISCONNECT"

		local msgtype = buffer(0, 1)

		local offset = 1
		local remain_length =0 
		offset, remain_length = lengthDecode(buffer, offset)

		local msgindex = msgtype:bitfield(0,4)

		local subtree = tree:add(MQTTPROTO, buffer())
		local fixheader_subtree = subtree:add("Fixed Header", nil)

		subtree:append_text(", Message Type: " .. msg_types[msgindex])

		fixheader_subtree:add(f.message_type, msgtype)
		fixheader_subtree:add(f.dup, msgtype)
		fixheader_subtree:add(f.qos, msgtype)
		fixheader_subtree:add(f.retain, msgtype)

		fixheader_subtree:add(f.remain_length, remain_length)

		local fixhdr_qos = msgtype:bitfield(5,2)
		subtree:append_text(", QoS: " .. fixhdr_qos)

		local topic = nil
		local message_id = nil
		local info = msg_types[msgindex]

		if(msgindex == 1) then -- CONNECT
			local varhdr_init = offset -- For calculating variable header size
			local varheader_subtree = subtree:add("Variable Header", nil)

			local name_len = buffer(offset, 2):uint()
			offset = offset + 2
			local name = buffer(offset, name_len)
			offset = offset + name_len
			local version = buffer(offset, 1)
			offset = offset + 1
			local flags = buffer(offset, 1)
			offset = offset + 1
			local keepalive = buffer(offset, 2)
			offset = offset + 2

			varheader_subtree:add(f.connect_protocol_name, name)
			varheader_subtree:add(f.connect_protocol_version, version)

			local flags_subtree = varheader_subtree:add("Flags", nil)
			flags_subtree:add(f.connect_username, flags)
			flags_subtree:add(f.connect_password, flags)
			flags_subtree:add(f.connect_will_retain, flags)
			flags_subtree:add(f.connect_will_qos, flags)
			flags_subtree:add(f.connect_will, flags)
			flags_subtree:add(f.connect_clean_session, flags)

			varheader_subtree:add(f.connect_keep_alive, keepalive)
			local payload_re_subtree = subtree:add("Payload Regular", nil)
			local payload_subtree = subtree:add("Payload", nil)

			local data_len = remain_length - (offset - varhdr_init)
			local data = buffer(offset, data_len)

			data_uncompress = data:uncompress()

			offset = offset + data_len
			payload_re_subtree:add(f.payload_re_data, data)
			payload_subtree:add(f.payload_data, data_uncompress)




		elseif(msgindex == 3) then -- PUBLISH
			local varhdr_init = offset -- For calculating variable header size
			local varheader_subtree = subtree:add("Variable Header", nil)

			local topic_len = buffer(offset, 2):uint()
			offset = offset + 2
			topic = buffer(offset, topic_len)
			offset = offset + topic_len

			varheader_subtree:add(f.publish_topic, topic)

			if(fixhdr_qos > 0) then
				message_id = buffer(offset, 2)
				offset = offset + 2
				varheader_subtree:add(f.publish_message_id, message_id)
			end

			local payload_subtree = subtree:add("Payload", nil)
			-- Data
			local data_len = remain_length - (offset - varhdr_init)
			-- print('start debuging----')
			-- print(remain_length)

			-- print(topic)
			if topic == "2f745f6f6d6e6973746f72655f73796e63" then
				print(offset)
				print(data_len)
			end

			-- print(varhdr_init)
			local data = buffer(offset, data_len)
			-- if data(0, 1):string() == '{' then
			-- 	Dissector.get("json"):call(data, pinfo, tree)
			-- end
			-- print(Struct.fromhex(data))
			payload_subtree:add(f.payload_re_data, data)
			data = data:uncompress()

			-- print('end debuging----')
			offset = offset + data_len

			if data ~= nil then
				local tvbdata = data:tvb()
				if tvbdata(0, 1):string() == '{' then
					Dissector.get("json"):call(tvbdata, pinfo, tree)
				end
				payload_subtree:add(f.payload_data, data)
			end
		elseif(msgindex == 4) then -- PUBACK
			message_id = buffer(offset, 2)
			offset = offset + 2
			subtree:add(f.publish_message_id, message_id)

		elseif(msgindex == 8 or msgindex == 10) then -- SUBSCRIBE & UNSUBSCRIBE
			local varheader_subtree = subtree:add("Variable Header", nil)

			message_id = buffer(offset, 2)
			offset = offset + 2
			varheader_subtree:add(f.subscribe_message_id, message_id)

			local payload_subtree = subtree:add("Payload", nil)
			while(offset < buffer:len()) do
				local topic_len = buffer(offset, 2):uint()
				offset = offset + 2
				topic = buffer(offset, topic_len)
				offset = offset + topic_len

				payload_subtree:add(f.publish_topic, topic)
				if(msgindex == 8) then -- QoS byte only for subscription
					payload_subtree:add(f.subscribe_qos, qos)
				end
			end

		elseif(msgindex == 9 or msgindex == 11) then -- SUBACK & UNSUBACK
			local varheader_subtree = subtree:add("Variable Header", nil)

			message_id = buffer(offset, 2)
			offset = offset + 2
			varheader_subtree:add(f.suback_message_id, message_id)

			local payload_subtree = subtree:add("Payload", nil)
			while(offset < buffer:len()) do
				local qos = buffer(offset, 1)
				offset = offset + 1
				payload_subtree:add(f.suback_qos, qos);
			end

		else
			if((buffer:len()-offset) > 0) then
				local payload_subtree = subtree:add("Payload", nil)
				payload_subtree:add(f.payload_data, buffer(offset, buffer:len()-offset))
			end
		end

		if topic then
			subtree:append_text(", Topic: " .. topic:string())
			info = info .. " " .. topic:string()
		end
		if message_id then
			info = info .. " (id=" .. message_id:uint() .. ")"
		end

		pinfo.cols.info:set(info)

	end

	-- Register the dissector
	-- tcp_table = DissectorTable.get("ssl.port")
	-- tcp_table:add(443, MQTTPROTO)
	-- tcp_table:add(32763, MQTTPROTO)
	tcp_table = DissectorTable.get("tcp.port")
	tcp_table:add(443, MQTTPROTO)
	tcp_table:add(32763, MQTTPROTO)
end
