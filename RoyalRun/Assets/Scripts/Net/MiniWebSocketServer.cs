using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace RoyalRun.Net
{
    // An event that the network thread puts into a queue and the game reads in Update().
    public enum ServerEventType { Connected, Message, Disconnected }

    public struct ServerEvent
    {
        public ServerEventType Type;
        public int ClientId;
        public string Text;
    }

    // A tiny HTTP + WebSocket server with no external libraries.
    //  GET /     -> serves the controller HTML page (the phone opens it)
    //  GET /ws   -> upgrades to WebSocket, then JSON text is exchanged
    // There are no Unity classes here, so the file can be tested separately from the editor.
    public class MiniWebSocketServer
    {
        const string WsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        const int MaxMessageBytes = 64 * 1024;

        class Client
        {
            public int Id;
            public TcpClient Tcp;
            public NetworkStream Stream;
            public readonly object WriteLock = new object();
            public volatile bool Alive = true;
            public bool Raw;     // a game (not a browser): plain lines of JSON instead of WebSocket frames
        }

        readonly Func<string> pageProvider;   // returns the page HTML (it can change, e.g. with the language)
        readonly ConcurrentQueue<ServerEvent> events = new ConcurrentQueue<ServerEvent>();
        readonly Dictionary<int, Client> clients = new Dictionary<int, Client>();
        readonly object clientsLock = new object();

        TcpListener listener;
        Thread acceptThread;
        Thread heartbeatThread;
        volatile bool running;
        int nextId = 1;

        public int Port { get; private set; }
        public int HttpHits;        // how many times phones (or anyone) requested the page
        public int WsTotal;         // how many WebSocket connections there have been in total
        public int ClientCount { get { lock (clientsLock) { return clients.Count; } } }
        public bool IsRunning { get { return running; } }
        public Action<string> Log = delegate { };

        // GET /rr-info answers with this JSON (a Wi-Fi race room describes itself to searching phones).
        // Called on a network thread: it must not touch Unity objects.
        public Func<string> InfoProvider;

        public MiniWebSocketServer(string htmlPage) : this(() => htmlPage)
        {
        }

        // The provider is called on a network thread for every page request,
        // so it must not touch Unity objects.
        public MiniWebSocketServer(Func<string> pageProvider)
        {
            this.pageProvider = pageProvider;
        }

        // Try startPort; if it is busy, try the next ones (up to +10).
        public bool Start(int startPort)
        {
            for (int p = startPort; p <= startPort + 10; p++)
            {
                try
                {
                    listener = new TcpListener(IPAddress.Any, p);
                    listener.Start();
                    Port = p;
                    break;
                }
                catch (SocketException)
                {
                    listener = null;
                }
            }
            if (listener == null) return false;

            running = true;
            acceptThread = new Thread(AcceptLoop) { IsBackground = true, Name = "RR-Accept" };
            acceptThread.Start();
            heartbeatThread = new Thread(HeartbeatLoop) { IsBackground = true, Name = "RR-Heartbeat" };
            heartbeatThread.Start();
            return true;
        }

        public void Stop()
        {
            running = false;
            try { if (listener != null) listener.Stop(); } catch { }
            List<Client> copy;
            lock (clientsLock) { copy = new List<Client>(clients.Values); clients.Clear(); }
            foreach (Client c in copy) CloseClient(c, false);
        }

        public bool TryDequeue(out ServerEvent ev)
        {
            return events.TryDequeue(out ev);
        }

        public void Send(int clientId, string text)
        {
            Client c;
            lock (clientsLock) { clients.TryGetValue(clientId, out c); }
            if (c == null || !c.Alive) return;
            if (c.Raw) SendRaw(c, text);
            else SendFrame(c, 0x1, Encoding.UTF8.GetBytes(text));
        }

        public void Broadcast(string text)
        {
            List<Client> copy;
            lock (clientsLock) { copy = new List<Client>(clients.Values); }
            byte[] data = Encoding.UTF8.GetBytes(text);
            foreach (Client c in copy)
            {
                if (!c.Alive) continue;
                if (c.Raw) SendRaw(c, text);
                else SendFrame(c, 0x1, data);
            }
        }

        public void Disconnect(int clientId)
        {
            Client c;
            lock (clientsLock) { clients.TryGetValue(clientId, out c); }
            if (c != null) CloseClient(c, true);
        }

        // ---------- accepting connections ----------

        void AcceptLoop()
        {
            while (running)
            {
                TcpClient tcp;
                try { tcp = listener.AcceptTcpClient(); }
                catch { break; }

                TcpClient captured = tcp;
                Thread t = new Thread(() => ClientLoop(captured)) { IsBackground = true, Name = "RR-Client" };
                t.Start();
            }
        }

        void ClientLoop(TcpClient tcp)
        {
            Client client = null;
            try
            {
                tcp.NoDelay = true;
                tcp.ReceiveTimeout = 8000;
                tcp.SendTimeout = 8000;
                NetworkStream stream = tcp.GetStream();

                string request = ReadHttpHeader(stream);
                if (request == null) { tcp.Close(); return; }

                string[] lines = request.Split(new[] { "\r\n" }, StringSplitOptions.None);
                string[] first = lines[0].Split(' ');
                string path = first.Length > 1 ? first[1] : "/";
                int q = path.IndexOf('?');
                if (q >= 0) path = path.Substring(0, q);

                Dictionary<string, string> headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                for (int i = 1; i < lines.Length; i++)
                {
                    int c = lines[i].IndexOf(':');
                    if (c > 0) headers[lines[i].Substring(0, c).Trim()] = lines[i].Substring(c + 1).Trim();
                }

                string key;
                bool isUpgrade = headers.TryGetValue("Sec-WebSocket-Key", out key)
                                 && headers.ContainsKey("Upgrade")
                                 && headers["Upgrade"].ToLowerInvariant().Contains("websocket");

                string remote = tcp.Client.RemoteEndPoint != null ? tcp.Client.RemoteEndPoint.ToString() : "?";

                // another copy of the game joins a Wi-Fi race: after the answer, lines of JSON go both ways
                if (path == "/rrnet")
                {
                    byte[] ok = Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: rrnet\r\nConnection: Upgrade\r\n\r\n");
                    stream.Write(ok, 0, ok.Length);
                    stream.Flush();
                    tcp.ReceiveTimeout = 15000;
                    Log("Game connected: " + remote);
                    client = new Client { Id = Interlocked.Increment(ref nextId), Tcp = tcp, Stream = stream, Raw = true };
                    lock (clientsLock) { clients[client.Id] = client; }
                    events.Enqueue(new ServerEvent { Type = ServerEventType.Connected, ClientId = client.Id, Text = remote });
                    ReadLines(client);
                    return;
                }

                if (!isUpgrade)
                {
                    Interlocked.Increment(ref HttpHits);
                    Log("HTTP request " + path + " from " + remote);
                    ServeHttp(stream, path);
                    tcp.Close();
                    return;
                }

                string accept;
                using (SHA1 sha1 = SHA1.Create())
                    accept = Convert.ToBase64String(sha1.ComputeHash(Encoding.ASCII.GetBytes(key + WsGuid)));
                string response =
                    "HTTP/1.1 101 Switching Protocols\r\n" +
                    "Upgrade: websocket\r\n" +
                    "Connection: Upgrade\r\n" +
                    "Sec-WebSocket-Accept: " + accept + "\r\n\r\n";
                byte[] rb = Encoding.ASCII.GetBytes(response);
                stream.Write(rb, 0, rb.Length);

                // after the handshake: a ping every 5 s, so 15 s of silence = the client is gone
                tcp.ReceiveTimeout = 15000;

                Interlocked.Increment(ref WsTotal);
                Log("WebSocket connected: " + remote);
                client = new Client { Id = Interlocked.Increment(ref nextId), Tcp = tcp, Stream = stream };
                lock (clientsLock) { clients[client.Id] = client; }
                events.Enqueue(new ServerEvent { Type = ServerEventType.Connected, ClientId = client.Id });

                ReadLoop(client);
            }
            catch (Exception e)
            {
                Log("client error: " + e.Message);
            }
            finally
            {
                if (client != null) CloseClient(client, true);
                else { try { tcp.Close(); } catch { } }
            }
        }

        static string ReadHttpHeader(NetworkStream stream)
        {
            byte[] buf = new byte[8192];
            int len = 0;
            while (len < buf.Length)
            {
                int n = stream.Read(buf, len, buf.Length - len);
                if (n <= 0) return null;
                len += n;
                string s = Encoding.ASCII.GetString(buf, 0, len);
                int end = s.IndexOf("\r\n\r\n", StringComparison.Ordinal);
                if (end >= 0) return s.Substring(0, end);
            }
            return null;
        }

        void ServeHttp(NetworkStream stream, string path)
        {
            byte[] body;
            string status;
            string type = "text/html; charset=utf-8";

            if (path == "/" || path == "/index.html")
            {
                status = "200 OK";
                body = Encoding.UTF8.GetBytes(pageProvider());
            }
            else if (path == "/rr-info" && InfoProvider != null)
            {
                status = "200 OK";
                body = Encoding.UTF8.GetBytes(InfoProvider());
                type = "application/json; charset=utf-8";
            }
            else if (path == "/ping")
            {
                status = "200 OK";
                body = Encoding.UTF8.GetBytes("ok");
                type = "text/plain; charset=utf-8";
            }
            else if (path == "/favicon.ico")
            {
                status = "204 No Content";
                body = new byte[0];
            }
            else
            {
                status = "404 Not Found";
                body = Encoding.UTF8.GetBytes("Not found");
                type = "text/plain; charset=utf-8";
            }

            string head =
                "HTTP/1.1 " + status + "\r\n" +
                "Content-Type: " + type + "\r\n" +
                "Content-Length: " + body.Length + "\r\n" +
                "Cache-Control: no-store\r\n" +
                "Connection: close\r\n\r\n";
            byte[] hb = Encoding.ASCII.GetBytes(head);
            stream.Write(hb, 0, hb.Length);
            if (body.Length > 0) stream.Write(body, 0, body.Length);
            stream.Flush();
        }

        // ---------- reading lines (game clients) ----------

        void ReadLines(Client c)
        {
            MemoryStream line = new MemoryStream();
            byte[] buf = new byte[4096];
            while (running && c.Alive)
            {
                int n = c.Stream.Read(buf, 0, buf.Length);
                if (n <= 0) return;
                for (int i = 0; i < n; i++)
                {
                    if (buf[i] == (byte)'\n')
                    {
                        if (line.Length > 0)
                        {
                            events.Enqueue(new ServerEvent
                            {
                                Type = ServerEventType.Message,
                                ClientId = c.Id,
                                Text = Encoding.UTF8.GetString(line.ToArray())
                            });
                        }
                        line.SetLength(0);
                    }
                    else if (buf[i] != (byte)'\r')
                    {
                        line.WriteByte(buf[i]);
                        if (line.Length > MaxMessageBytes) return;
                    }
                }
            }
        }

        void SendRaw(Client c, string text)
        {
            try
            {
                byte[] data = Encoding.UTF8.GetBytes(text + "\n");
                lock (c.WriteLock)
                {
                    c.Stream.Write(data, 0, data.Length);
                    c.Stream.Flush();
                }
            }
            catch
            {
                CloseClient(c, true);
            }
        }

        // ---------- reading WebSocket frames ----------

        void ReadLoop(Client c)
        {
            MemoryStream message = new MemoryStream();
            int messageOpcode = 0;

            while (running && c.Alive)
            {
                int b0 = c.Stream.ReadByte();
                int b1 = c.Stream.ReadByte();
                if (b0 < 0 || b1 < 0) return;

                bool fin = (b0 & 0x80) != 0;
                int opcode = b0 & 0x0F;
                bool masked = (b1 & 0x80) != 0;
                long length = b1 & 0x7F;

                if (length == 126)
                {
                    byte[] ext = ReadExact(c.Stream, 2);
                    if (ext == null) return;
                    length = (ext[0] << 8) | ext[1];
                }
                else if (length == 127)
                {
                    byte[] ext = ReadExact(c.Stream, 8);
                    if (ext == null) return;
                    length = 0;
                    for (int i = 0; i < 8; i++) length = (length << 8) | ext[i];
                }

                if (length > MaxMessageBytes) return;

                byte[] mask = null;
                if (masked)
                {
                    mask = ReadExact(c.Stream, 4);
                    if (mask == null) return;
                }

                byte[] payload = ReadExact(c.Stream, (int)length);
                if (payload == null) return;
                if (masked)
                    for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i % 4];

                switch (opcode)
                {
                    case 0x8: // close
                        return;
                    case 0x9: // ping -> pong
                        SendFrame(c, 0xA, payload);
                        break;
                    case 0xA: // pong
                        break;
                    case 0x1:
                    case 0x2:
                    case 0x0:
                        if (opcode != 0x0) { message.SetLength(0); messageOpcode = opcode; }
                        message.Write(payload, 0, payload.Length);
                        if (message.Length > MaxMessageBytes) return;
                        if (fin)
                        {
                            if (messageOpcode == 0x1)
                            {
                                events.Enqueue(new ServerEvent
                                {
                                    Type = ServerEventType.Message,
                                    ClientId = c.Id,
                                    Text = Encoding.UTF8.GetString(message.ToArray())
                                });
                            }
                            message.SetLength(0);
                        }
                        break;
                }
            }
        }

        static byte[] ReadExact(Stream s, int count)
        {
            byte[] buf = new byte[count];
            int got = 0;
            while (got < count)
            {
                int n = s.Read(buf, got, count - got);
                if (n <= 0) return null;
                got += n;
            }
            return buf;
        }

        // ---------- sending ----------

        void SendFrame(Client c, int opcode, byte[] payload)
        {
            try
            {
                byte[] header;
                if (payload.Length < 126)
                {
                    header = new byte[] { (byte)(0x80 | opcode), (byte)payload.Length };
                }
                else if (payload.Length <= 0xFFFF)
                {
                    header = new byte[] { (byte)(0x80 | opcode), 126, (byte)(payload.Length >> 8), (byte)(payload.Length & 0xFF) };
                }
                else
                {
                    header = new byte[10];
                    header[0] = (byte)(0x80 | opcode);
                    header[1] = 127;
                    long l = payload.Length;
                    for (int i = 0; i < 8; i++) header[9 - i] = (byte)((l >> (8 * i)) & 0xFF);
                }

                lock (c.WriteLock)
                {
                    c.Stream.Write(header, 0, header.Length);
                    if (payload.Length > 0) c.Stream.Write(payload, 0, payload.Length);
                    c.Stream.Flush();
                }
            }
            catch
            {
                CloseClient(c, true);
            }
        }

        void HeartbeatLoop()
        {
            while (running)
            {
                Thread.Sleep(5000);
                List<Client> copy;
                lock (clientsLock) { copy = new List<Client>(clients.Values); }
                foreach (Client c in copy)
                {
                    if (!c.Alive) continue;
                    if (c.Raw) SendRaw(c, "{\"t\":\"ping\"}");
                    else SendFrame(c, 0x9, new byte[0]);
                }
            }
        }

        void CloseClient(Client c, bool raiseEvent)
        {
            if (!c.Alive) return;
            c.Alive = false;

            bool wasRegistered;
            lock (clientsLock) { wasRegistered = clients.Remove(c.Id); }

            try { c.Tcp.Close(); } catch { }

            if (raiseEvent && wasRegistered)
                events.Enqueue(new ServerEvent { Type = ServerEventType.Disconnected, ClientId = c.Id });
        }
    }
}
