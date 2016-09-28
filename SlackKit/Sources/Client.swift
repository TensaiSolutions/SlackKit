//
//  Client.swift
//
// Copyright © 2016 Peter Zignego,  All rights reserved.
// Adapted to use Vapor by Philip Sidell
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Jay
import Vapor
import HTTP


public class SlackClient {

    internal(set) public var connected = false
    internal(set) public var authenticated = false
    internal(set) public var authenticatedUser: User?
    internal(set) public var team: Team?

    internal(set) public var channels = [String: Channel]()
    internal(set) public var users = [String: User]()
    internal(set) public var userGroups = [String: UserGroup]()
    internal(set) public var bots = [String: Bot]()
    internal(set) public var files = [String: File]()
    internal(set) public var sentMessages = [String: Message]()

    //MARK: - Delegates
    public weak var slackEventsDelegate: SlackEventsDelegate?
    public weak var messageEventsDelegate: MessageEventsDelegate?
    public weak var doNotDisturbEventsDelegate: DoNotDisturbEventsDelegate?
    public weak var channelEventsDelegate: ChannelEventsDelegate?
    public weak var groupEventsDelegate: GroupEventsDelegate?
    public weak var fileEventsDelegate: FileEventsDelegate?
    public weak var pinEventsDelegate: PinEventsDelegate?
    public weak var starEventsDelegate: StarEventsDelegate?
    public weak var reactionEventsDelegate: ReactionEventsDelegate?
    public weak var teamEventsDelegate: TeamEventsDelegate?
    public weak var subteamEventsDelegate: SubteamEventsDelegate?
    public weak var teamProfileEventsDelegate: TeamProfileEventsDelegate?

    internal var token = "SLACK_AUTH_TOKEN"

    public func setAuthToken(token: String) {
        self.token = token
    }

    public var webAPI: SlackWebAPI {
        return SlackWebAPI(slackClient: self)
    }

    internal var socket: WebSocket?
    internal let api = NetworkInterface()


    internal var ping: Double?
    internal var pong: Double?

    internal var pingInterval: Double?
    internal var timeout: Double?
    internal var reconnect: Bool?

    required public init(apiToken: String) {
        self.token = apiToken
    }

    public func connect(simpleLatest: Bool? = nil, noUnreads: Bool? = nil, mpimAware: Bool? = nil, pingInterval: Double? = nil, timeout: Double? = nil, reconnect: Bool? = nil) {
        self.pingInterval = pingInterval
        self.timeout = timeout
        self.reconnect = reconnect



        webAPI.rtmStart(simpleLatest: simpleLatest, noUnreads: noUnreads, mpimAware: mpimAware, success: {
            (response) -> Void in
            self.initialSetup(json: response)
            if let socketURL = response["url"] as? String {
                do {

                    try WebSocket.connect(to: socketURL) {
                        ws in
                        print("Connected to \(socketURL)")
                        self.setupSocket(socket: ws)
                    }
                } catch {

                }
            }
           }, failure:nil)
    }

    //MARK: - RTM Message send
    public func sendMessage(message: String, channelID: String) {
        if (connected) {
            if let data = formatMessageToSlackJsonString(message: message, channel: channelID) {
                if let string = try? data.string() {
                    _ = try? socket?.send(string)
                }
            }
        }
    }

    private func formatMessageToSlackJsonString(message: String, channel: String) -> Data? {
        let json: [String: Any] = [
            "id": Time.slackTimestamp(),
            "type": "message",
            "channel": channel,
            "text": message.slackFormatEscaping()
        ]

        do {
            let bytes = try Jay().dataFromJson(any: json)
            return Data(bytes)
        } catch {
            return nil
        }
    }

    private func addSentMessage(dictionary: [String: Any]) {
        var message = dictionary
        let ts = message["id"] as? Int
        message.removeValue(forKey:"id")
        message["ts"] = "\(ts)"
        message["user"] = self.authenticatedUser?.id
        sentMessages["\(ts)"] = Message(message: message)
    }

    //MARK: - Client setup
    private func initialSetup(json: [String: Any]) {
        team = Team(team: json["team"] as? [String: Any])
        authenticatedUser = User(user: json["self"] as? [String: Any])
        authenticatedUser?.doNotDisturbStatus = DoNotDisturbStatus(status: json["dnd"] as? [String: Any])
        enumerateObjects(array: json["users"] as? Array) { (user) in self.addUser(aUser: user) }
        enumerateObjects(array: json["channels"] as? Array) { (channel) in self.addChannel(aChannel: channel) }
        enumerateObjects(array: json["groups"] as? Array) { (group) in self.addChannel(aChannel: group) }
        enumerateObjects(array: json["mpims"] as? Array) { (mpim) in self.addChannel(aChannel: mpim) }
        enumerateObjects(array: json["ims"] as? Array) { (ims) in self.addChannel(aChannel: ims) }
        enumerateObjects(array: json["bots"] as? Array) { (bots) in self.addBot(aBot: bots) }
        enumerateSubteams(subteams: json["subteams"] as? [String: Any])
    }

    private func addUser(aUser: [String: Any]) {
        if let user = User(user: aUser), let id = user.id {
            users[id] = user
        }
    }

    private func addChannel(aChannel: [String: Any]) {
        if let channel = Channel(channel: aChannel), let id = channel.id {
            channels[id] = channel
        }
    }

    private func addBot(aBot: [String: Any]) {
        if let bot = Bot(bot: aBot), let id = bot.id {
            bots[id] = bot
        }
    }

    private func enumerateSubteams(subteams: [String: Any]?) {
        if let subteams = subteams {
            if let all = subteams["all"] as? [Any] {
                for item in all {
                    let u = UserGroup(userGroup: item as? [String: Any])
                    self.userGroups[u!.id!] = u
                }
            }
            if let auth = subteams["self"] as? [String] {
                for item in auth {
                    authenticatedUser?.userGroups = [String: String]()
                    authenticatedUser?.userGroups![item] = item
                }
            }
        }
    }

    // MARK: - Utilities
    private func enumerateObjects(array: [Any]?, initalizer: ([String: Any])-> Void) {
        if let array = array {
            for object in array {
                if let dictionary = object as? [String: Any] {
                    initalizer(dictionary)
                }
            }
        }
    }


    // MARK: - WebSocket

    private func setupSocket(socket: WebSocket) {
        socket.onText = { ws, text in
            print("[event] - \(text)")
            self.websocketDidReceive(message: text)
        }

        socket.onPing = { ws, frame in
            try ws.pong()
        }

        socket.onPong = { ws, frame in
            try ws.ping()
        }

        socket.onClose = { _, code, reason, clean in
            print("[ws close] \(clean ? "clean" : "dirty") \(code?.description ?? "") \(reason ?? "")")
            self.websocketDidDisconnect()
        }

        self.socket = socket
    }

    private func websocketDidReceive(message: String) {
        do {

              if let json = try Jay().anyJsonFromData((message.data(using: String.Encoding.utf8)?.makeBytes())!) as? [String:Any] {
                dispatch(event: json)
              }
            } catch {

            }
    }

    private func websocketDidDisconnect() {
        connected = false
        authenticated = false
        socket = nil
        authenticatedUser = nil
        slackEventsDelegate?.clientDisconnected()
        if reconnect == true {
            connect(pingInterval: pingInterval, timeout: timeout, reconnect: reconnect)
        }
    }

}
