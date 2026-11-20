using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace RoyalRun.Net
{
    // A connection from one copy of the game to the race host (another phone or a computer).
    // It speaks plain lines of JSON over TCP after a tiny HTTP "upgrade" (GET /rrnet).
    // Like the server, it never touches Unity objects: received lines wait in a queue for Update().
    public class NetLink
    {
        TcpClient tcp;
        NetworkStream stream;
        readonly object writeLock = new object();
        readonly ConcurrentQueue<string> inbox = new ConcurrentQueue<string>();
        volatile bool alive;
        volatile bool failed;

        public bool Connected { get { return alive; } }
        public bool Failed { get { return failed; } }   // the connection broke (or never opened)
        public string Host { get; private set; }

        // Connects in the background; check Connected / Failed later.
        public void ConnectAsync(string host, int port)
        {
            Host = host;
            Thread t = new Thread(() => Connect(host, port)) { IsBackground = true, Name = "RR-Link" };
            t.Start();
        }

        void Connect(string host, int port)
        {
            try
            {
                tcp = new TcpClient();
                IAsyncResult ar = tcp.BeginConnect(host, port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(3000) || !tcp.Connected) { failed = true; Close(); return; }
                tcp.EndConnect(ar);
                tcp.NoDelay = true;
                tcp.ReceiveTimeout = 15000;
                stream = tcp.GetStream();

                byte[] req = Encoding.ASCII.GetBytes("GET /rrnet HTTP/1.1\r\nHost: " + host + "\r\nUpgrade: rrnet\r\nConnection: Upgrade\r\n\r\n");
                stream.Write(req, 0, req.Length);

                // read the answer header byte by byte, so nothing after it is lost
                StringBuilder head = new StringBuilder();
                while (!head.ToString().EndsWith("\r\n\r\n", StringComparison.Ordinal))
                {
                    int b = stream.ReadByte();
                    if (b < 0 || head.Length > 4096) { failed = true; Close(); return; }
                    head.Append((char)b);
                }
                if (!head.ToString().StartsWith("HTTP/1.1 101", StringComparison.Ordinal)) { failed = true; Close(); return; }

                alive = true;
                ReadLoop();
            }
            catch
            {
                failed = true;
            }
            finally
            {
                if (alive) { alive = false; failed = true; }
                Close();
            }
        }

        void ReadLoop()
        {
            MemoryStream line = new MemoryStream();
            byte[] buf = new byte[4096];
            while (alive)
            {
                int n = stream.Read(buf, 0, buf.Length);
                if (n <= 0) return;
                for (int i = 0; i < n; i++)
                {
                    if (buf[i] == (byte)'\n')
                    {
                        if (line.Length > 0) inbox.Enqueue(Encoding.UTF8.GetString(line.ToArray()));
                        line.SetLength(0);
                    }
                    else if (buf[i] != (byte)'\r')
                    {
                        line.WriteByte(buf[i]);
                        if (line.Length > 64 * 1024) return;
                    }
                }
            }
        }

        public bool TryReceive(out string line)
        {
            return inbox.TryDequeue(out line);
        }

        public void Send(string json)
        {
            if (!alive || stream == null) return;
            try
            {
                byte[] data = Encoding.UTF8.GetBytes(json + "\n");
                lock (writeLock)
                {
                    stream.Write(data, 0, data.Length);
                    stream.Flush();
                }
            }
            catch
            {
                alive = false;
                failed = true;
                Close();
            }
        }

        public void Close()
        {
            alive = false;
            try { if (tcp != null) tcp.Close(); } catch { }
        }
    }

    // One race room found on the local network.
    public struct FoundRoom
    {
        public string Ip;
        public int Port;
        public string Json;      // the answer of GET /rr-info
    }

    // Finds race rooms on the same Wi-Fi: asks every address of the local /24 network (x.x.x.1 - x.x.x.254)
    // "GET /rr-info" on the race port, 48 addresses at a time, ~0.4 s per try. No broadcast packets are used,
    // so it also works on phones that filter broadcasts.
    public class NetScan
    {
        readonly ConcurrentQueue<FoundRoom> found = new ConcurrentQueue<FoundRoom>();
        volatile int pending;
        public bool Running { get { return pending > 0; } }

        public bool TryGet(out FoundRoom room)
        {
            return found.TryDequeue(out room);
        }

        public void Start(int port, string skipIp)
        {
            List<string> targets = new List<string>();
            foreach (string own in LocalAddresses())
            {
                string[] parts = own.Split('.');
                if (parts.Length != 4) continue;
                string prefix = parts[0] + "." + parts[1] + "." + parts[2] + ".";
                for (int i = 1; i < 255; i++)
                {
                    string ip = prefix + i;
                    if (ip == skipIp || targets.Contains(ip)) continue;
                    targets.Add(ip);
                }
            }
            targets.Add("127.0.0.1");   // a room on this very computer (testing with two copies)

            pending = targets.Count;
            int perThread = (targets.Count + 47) / 48;
            for (int t = 0; t < 48; t++)
            {
                List<string> slice = targets.GetRange(Math.Min(t * perThread, targets.Count),
                                                      Math.Max(0, Math.Min(perThread, targets.Count - t * perThread)));
                if (slice.Count == 0) continue;
                Thread th = new Thread(() =>
                {
                    foreach (string ip in slice)
                    {
                        Probe(ip, port);
                        Interlocked.Decrement(ref pending);
                    }
                }) { IsBackground = true, Name = "RR-Scan" };
                th.Start();
            }
        }

        void Probe(string ip, int port)
        {
            TcpClient c = new TcpClient();
            try
            {
                IAsyncResult ar = c.BeginConnect(ip, port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(450) || !c.Connected) return;
                c.EndConnect(ar);
                c.ReceiveTimeout = 1000;
                NetworkStream s = c.GetStream();
                byte[] req = Encoding.ASCII.GetBytes("GET /rr-info HTTP/1.1\r\nHost: " + ip + "\r\nConnection: close\r\n\r\n");
                s.Write(req, 0, req.Length);
                MemoryStream ms = new MemoryStream();
                byte[] buf = new byte[2048];
                int n;
                while (ms.Length < 8192 && (n = s.Read(buf, 0, buf.Length)) > 0) ms.Write(buf, 0, n);
                string text = Encoding.UTF8.GetString(ms.ToArray());
                int body = text.IndexOf("\r\n\r\n", StringComparison.Ordinal);
                if (!text.StartsWith("HTTP/1.1 200", StringComparison.Ordinal) || body < 0) return;
                string json = text.Substring(body + 4).Trim();
                if (json.StartsWith("{", StringComparison.Ordinal) && json.Contains("royalrun"))
                    found.Enqueue(new FoundRoom { Ip = ip, Port = port, Json = json });
            }
            catch { }
            finally
            {
                try { c.Close(); } catch { }
            }
        }

        // The device's IPv4 addresses on the local network (Wi-Fi first).
        public static List<string> LocalAddresses()
        {
            List<string> result = new List<string>();
            try
            {
                foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                    foreach (UnicastIPAddressInformation ua in ni.GetIPProperties().UnicastAddresses)
                    {
                        if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                        string ip = ua.Address.ToString();
                        if (ip.StartsWith("169.254.") || ip.StartsWith("127.")) continue;
                        if (ip.StartsWith("192.168.")) result.Insert(0, ip); else result.Add(ip);
                    }
                }
            }
            catch { }

            // Some phones do not list their interfaces: ask the system which address it would use
            // to reach the outside (no packet is sent by a UDP "connect").
            try
            {
                using (Socket s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
                {
                    s.Connect("8.8.8.8", 53);
                    IPEndPoint ep = s.LocalEndPoint as IPEndPoint;
                    if (ep != null)
                    {
                        string ip = ep.Address.ToString();
                        if (!ip.StartsWith("127.") && !ip.StartsWith("0.") && !result.Contains(ip)) result.Insert(0, ip);
                    }
                }
            }
            catch { }
            return result;
        }
    }
}
