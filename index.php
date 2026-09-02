<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="BKC Lic - By TranHa - Công cụ quản lý và kích hoạt bản quyền Windows/Office toàn diện, dọn dẹp hệ thống.">
    <title>BKC Lic - By TranHa</title>
    
    <!-- Google Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    
    <link rel="stylesheet" href="style.css?v=9">
</head>
<body>
    <div class="blob-bg">
        <div class="blob blob-1"></div>
        <div class="blob blob-2"></div>
    </div>

    <header class="glass-header">
        <div class="container header-container">
            <div class="logo">
                <img src="logo.png" alt="BKC Logo" style="height: 40px; margin-right: 10px; object-fit: contain;">
            </div>
            <nav>
                <ul>
                    <li><a href="#features">Tính năng</a></li>
                    <li><a href="#how-it-works">Hướng dẫn</a></li>
                    <li>
                        <button class="theme-toggle" id="themeToggle" aria-label="Đổi giao diện">
                            <!-- SVG Sun/Moon handled by JS -->
                            <svg viewBox="0 0 24 24"><path d="M12 21a9 9 0 1 1 0-18 9 9 0 0 1 0 18zm0-2a7 7 0 1 0 0-14 7 7 0 0 0 0 14z"/></svg>
                        </button>
                    </li>
                </ul>
            </nav>
        </div>
    </header>

    <main>
        <!-- Hero Section -->
        <section class="hero-section container">
            <div class="hero-content fade-in">
                <h1 class="gradient-text">Quản Lý Bản Quyền<br>Toàn Diện & Chuyên Nghiệp.</h1>
                <p class="hero-desc">Giải pháp "All-in-One" giúp bạn dễ dàng quét, dọn dẹp, sao lưu và kích hoạt an toàn cho hệ thống Windows & Microsoft Office chỉ với 1 Click.</p>
                
                <div class="terminal-container">
                    <div class="terminal-header">
                        <div class="dot red"></div>
                        <div class="dot yellow"></div>
                        <div class="dot green"></div>
                        <span class="terminal-title">Windows PowerShell (Admin)</span>
                    </div>
                    <div class="terminal-body">
                        <div>
                            <span class="prompt">PS C:\></span> 
                            <span class="command" id="typewriter-cmd"></span><span class="typewriter"></span>
                        </div>
                        <button class="copy-btn" onclick="copyCommand()">Copy Lệnh</button>
                    </div>
                </div>
                <p class="terminal-note">* Click Copy Lệnh, dán vào PowerShell (Run as Administrator) và nhấn Enter.</p>
            </div>
            
            <div class="hero-image fade-in delay-1">
                <div class="glass-mockup">
                    <div class="mockup-header">BKC Lic - Trình Quản Lý Bản Quyền Nâng Cao</div>
                    <div class="mockup-content">
                        <div class="mockup-row"><div class="mockup-btn blue"></div> Nạp Key Windows (Online)</div>
                        <div class="mockup-row"><div class="mockup-btn red"></div> Xóa Key / Crack Windows</div>
                        <div class="mockup-row"><div class="mockup-btn cyan"></div> Lấy IID / Nạp CID</div>
                        <div class="mockup-row"><div class="mockup-btn purple"></div> Quét Cấu Hình & Tối Ưu Hệ Thống</div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Stats Section -->
        <section class="stats-section">
            <div class="container stats-grid">
                <div class="stat-item fade-in">
                    <h2>1 Click</h2>
                    <p>Thao Tác Siêu Nhanh</p>
                </div>
                <div class="stat-item fade-in">
                    <h2>100%</h2>
                    <p>Sạch Sẽ & Không Mã Độc</p>
                </div>
                <div class="stat-item fade-in">
                    <h2>All-in-One</h2>
                    <p>Đa Năng & Tiện Dụng</p>
                </div>
            </div>
        </section>

        <!-- How It Works -->
        <section id="how-it-works" class="how-it-works container">
            <h2 class="section-title">Cách Sử Dụng Đơn Giản</h2>
            <div class="steps-container">
                <div class="step-card fade-in">
                    <div class="step-number">1</div>
                    <h3>Copy Lệnh</h3>
                    <p>Bấm vào nút Copy Lệnh trên trang web để sao chép mã tự động.</p>
                </div>
                <div class="step-card fade-in delay-1">
                    <div class="step-number">2</div>
                    <h3>Mở PowerShell</h3>
                    <p>Tìm kiếm PowerShell trong Start Menu và chọn Run as Administrator.</p>
                </div>
                <div class="step-card fade-in">
                    <div class="step-number">3</div>
                    <h3>Dán & Chạy</h3>
                    <p>Nhấp chuột phải để dán lệnh (Paste), sau đó nhấn Enter để mở công cụ.</p>
                </div>
            </div>
        </section>

        <!-- Features Section -->
        <section id="features" class="features-section container">
            <h2 class="section-title">Tính Năng Nổi Bật</h2>
            <div class="features-grid">
                <div class="feature-card fade-in">
                    <div class="feature-icon">
                        <svg viewBox="0 0 24 24"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                    </div>
                    <h3>An Toàn Tuyệt Đối</h3>
                    <p>Code mã nguồn mở, script PowerShell sạch 100%, không sử dụng các file chạy ngầm độc hại.</p>
                </div>
                
                <div class="feature-card fade-in">
                    <div class="feature-icon">
                        <svg viewBox="0 0 24 24"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>
                    </div>
                    <h3>Kích Hoạt Bản Quyền</h3>
                    <p>Hỗ trợ đa dạng phương thức nạp Key, lấy IID và tự động kích hoạt Windows/Office siêu tốc.</p>
                </div>
                
                <div class="feature-card fade-in">
                    <div class="feature-icon">
                        <svg viewBox="0 0 24 24"><path d="M3 3h18v18H3zM9 3v18M15 3v18M3 9h18M3 15h18"/></svg>
                    </div>
                    <h3>Quét & Xóa Crack</h3>
                    <p>Phát hiện và gỡ bỏ hoàn toàn các tool crack cũ như KMSpico, KMSAuto ra khỏi hệ thống của bạn.</p>
                </div>

                <div class="feature-card fade-in">
                    <div class="feature-icon">
                        <svg viewBox="0 0 24 24"><path d="M2 12h4l3-9 5 18 3-9h5"/></svg>
                    </div>
                    <h3>Quét Cấu Hình Máy</h3>
                    <p>Xem thông tin chi tiết về phần cứng máy tính: CPU, số khe RAM, dung lượng SSD/HDD, và Card đồ họa.</p>
                </div>
            </div>
        </section>
    </main>

    <footer class="glass-footer">
        <div class="container footer-content">
            <div class="footer-info">
                <h3>Bách Khoa PC</h3>
                <p>Cung cấp giải pháp phần mềm & phần cứng chuyên nghiệp.</p>
            </div>
            <div class="social-links">
                <a href="#" class="pill-btn">Zalo</a>
                <a href="#" class="pill-btn">Facebook</a>
                <a href="#" class="pill-btn">Hotline: 0968993355</a>
            </div>
            <div class="footer-copyright">
                &copy; <?php echo date("Y"); ?> BKC Lic. Designed with 💖 by TranHa.
            </div>
        </div>
    </footer>

    <!-- Scripts -->
    <script>
        // 1. Lệnh copy
        const cmdText = "irm lic.bachkhoapc.vn | iex";
        function copyCommand() {
            navigator.clipboard.writeText(cmdText).then(() => {
                const btn = document.querySelector('.copy-btn');
                const origText = btn.innerText;
                btn.innerText = "Đã Copy!";
                btn.style.background = "var(--cmd-prompt)";
                btn.style.color = "#fff";
                setTimeout(() => {
                    btn.innerText = origText;
                    btn.style.background = "var(--btn-bg)";
                    btn.style.color = "var(--text-primary)";
                }, 2000);
            });
        }

        // 2. Hiệu ứng gõ chữ Terminal
        let i = 0;
        function typeWriter() {
            if (i < cmdText.length) {
                document.getElementById("typewriter-cmd").innerHTML += cmdText.charAt(i);
                i++;
                setTimeout(typeWriter, 50);
            }
        }
        setTimeout(typeWriter, 1000); // Đợi 1s rồi gõ

        // 3. Dark/Light Mode Toggle
        const themeToggle = document.getElementById('themeToggle');
        const root = document.documentElement;
        
        // Icon mặt trời/mặt trăng (SVG)
        const sunIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>';
        const moonIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';

        // Đọc trạng thái đã lưu, mặc định là light
        const savedTheme = localStorage.getItem('theme') || 'light';
        root.setAttribute('data-theme', savedTheme);
        themeToggle.innerHTML = savedTheme === 'dark' ? sunIcon : moonIcon;

        themeToggle.addEventListener('click', () => {
            const currentTheme = root.getAttribute('data-theme');
            const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
            root.setAttribute('data-theme', newTheme);
            localStorage.setItem('theme', newTheme);
            themeToggle.innerHTML = newTheme === 'dark' ? sunIcon : moonIcon;
        });

        // 4. Fade-in on scroll (Intersection Observer)
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.style.animationPlayState = 'running';
                }
            });
        });
        document.querySelectorAll('.fade-in').forEach(el => {
            el.style.animationPlayState = 'paused';
            observer.observe(el);
        });
    </script>
</body>
</html>
