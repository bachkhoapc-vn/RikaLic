document.addEventListener('DOMContentLoaded', () => {
    // Copy to clipboard functionality
    const copyBtn = document.getElementById('copy-btn');
    const cmdText = document.getElementById('cmd-text').innerText;

    copyBtn.addEventListener('click', () => {
        navigator.clipboard.writeText(cmdText).then(() => {
            const originalText = copyBtn.innerText;
            copyBtn.innerText = 'Đã Copy!';
            copyBtn.style.background = 'rgba(39, 201, 63, 0.2)';
            copyBtn.style.color = '#27c93f';
            
            setTimeout(() => {
                copyBtn.innerText = originalText;
                copyBtn.style.background = '';
                copyBtn.style.color = '';
            }, 2000);
        }).catch(err => {
            console.error('Lỗi khi copy: ', err);
        });
    });

    // Scroll Fade-in Animation
    const fadeElements = document.querySelectorAll('.fade-in-scroll');
    
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };
    
    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('fade-in');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);
    
    fadeElements.forEach(el => {
        observer.observe(el);
    });
});
