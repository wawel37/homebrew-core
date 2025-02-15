class Condure < Formula
  include Language::Python::Virtualenv

  desc "HTTP/WebSocket connection manager"
  homepage "https://github.com/fanout/condure"
  url "https://github.com/fanout/condure/archive/refs/tags/1.10.0.tar.gz"
  sha256 "abe4d83ae2494a8eabd036f6f455fb4d8ebc71b29d8d50a0b35a7a59f8e0ea60"
  license "Apache-2.0"

  bottle do
    rebuild 2
    sha256 cellar: :any,                 arm64_ventura:  "b8f7485060a0404fccfce413b376bb43ff81d85856113adb7cec6b065dd39dcb"
    sha256 cellar: :any,                 arm64_monterey: "26e4eee328744f960f26f3a56f3cb2b4a3c364a9e3d7dd6062e00edae64eda5e"
    sha256 cellar: :any,                 sonoma:         "215af0aa8b1e3ab6973f92fed30ad87564c6731bc42106ac5d191381be9952d2"
    sha256 cellar: :any,                 ventura:        "761738779181959bccac2f1fcadd5d73703d499c3452163ff6b7e83536edd7e7"
    sha256 cellar: :any,                 monterey:       "a9a5ab1ac88709cca7e6e442f3f6c1664d2eb9c78973b02a174457f81d0df758"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "a41eb0f6718da809e72bec5dc08e58d2cd186a560a31a5c715fc91f10c384106"
  end

  depends_on "pkg-config" => :build
  depends_on "rust" => :build
  depends_on "cython" => :test # use brew cython as building it in test can cause time out
  depends_on "python@3.12" => :test
  depends_on "openssl@3"
  depends_on "zeromq"

  resource "packaging" do
    url "https://files.pythonhosted.org/packages/fb/2b/9b9c33ffed44ee921d0967086d653047286054117d584f1b1a7c22ceaf7b/packaging-23.2.tar.gz"
    sha256 "048fb0e9405036518eaaf48a55953c750c11e1a1b68e0dd1a9d62ed0c092cfc5"
  end

  resource "pyzmq" do
    url "https://files.pythonhosted.org/packages/3a/33/1a3683fc9a4bd64d8ccc0290da75c8f042184a1a49c146d28398414d3341/pyzmq-25.1.2.tar.gz"
    sha256 "93f1aa311e8bb912e34f004cf186407a4e90eec4f0ecc0efd26056bf7eda0226"
  end

  resource "setuptools" do
    url "https://files.pythonhosted.org/packages/c8/1f/e026746e5885a83e1af99002ae63650b7c577af5c424d4c27edcf729ab44/setuptools-69.1.1.tar.gz"
    sha256 "5c0806c7d9af348e6dd3777b4f4dbb42c7ad85b190104837488eab9a7c945cf8"
  end

  resource "tnetstring3" do
    url "https://files.pythonhosted.org/packages/d9/fd/737a371f539842f6fcece47bb6b941700c9f924e8543cd35c4f3a2e7cc6c/tnetstring3-0.3.1.tar.gz"
    sha256 "5acab57cce3693d119265a8ac019a9bcdc52a9cacb3ba37b5b3a1746a1c14d56"
  end

  def install
    # https://github.com/fanout/condure/issues/16
    inreplace "Cargo.toml", 'time = { version = "0.3", features = ["formatting", "local-offset", "macros"] }',
                            'time = { version = "0.3.36", features = ["formatting", "local-offset", "macros"] }'

    system "cargo", "install", *std_cargo_args
  end

  test do
    ipcfile = testpath/"client"
    runfile = testpath/"test.py"

    python3 = "python3.12"
    ENV.append_path "PYTHONPATH", Formula["cython"].opt_libexec/Language::Python.site_packages(python3)
    venv = virtualenv_create(testpath/"vendor", python3)
    venv.pip_install resources.reject { |r| r.name == "pyzmq" }
    venv.pip_install(resource("pyzmq"), build_isolation: false)

    runfile.write <<~EOS
      import threading
      from urllib.request import urlopen
      import tnetstring
      import zmq
      def server_worker(c):
        ctx = zmq.Context()
        sock = ctx.socket(zmq.REP)
        sock.connect('ipc://#{ipcfile}')
        c.acquire()
        c.notify()
        c.release()
        while True:
          m_raw = sock.recv()
          req = tnetstring.loads(m_raw[1:])
          resp = {}
          resp[b'id'] = req[b'id']
          resp[b'code'] = 200
          resp[b'reason'] = b'OK'
          resp[b'headers'] = [[b'Content-Type', b'text/plain']]
          resp[b'body'] = b'test response\\n'
          sock.send(b'T' + tnetstring.dumps(resp))
      c = threading.Condition()
      c.acquire()
      server_thread = threading.Thread(target=server_worker, args=(c,))
      server_thread.daemon = True
      server_thread.start()
      c.wait()
      c.release()
      with urlopen('http://localhost:10000/test') as f:
        body = f.read()
        assert(body == b'test response\\n')
    EOS

    pid = fork do
      exec bin/"condure", "--listen", "10000,req", "--zclient-req", "ipc://#{ipcfile}"
    end

    begin
      system testpath/"vendor/bin/python3", runfile
    ensure
      Process.kill("TERM", pid)
      Process.wait(pid)
    end
  end
end
