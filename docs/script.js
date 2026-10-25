// VMStart Official Website - JavaScript
// Language switching and interactions

let currentLang = 'zh';

function toggleLang() {
    currentLang = currentLang === 'zh' ? 'en' : 'zh';
    applyLang();
}

function applyLang() {
    const label = document.getElementById('lang-label');
    if (label) label.textContent = currentLang === 'zh' ? 'EN' : '中文';
    
    document.documentElement.lang = currentLang === 'zh' ? 'zh-CN' : 'en';
    
    document.querySelectorAll('[data-zh][data-en]').forEach(el => {
        const text = el.getAttribute(`data-${currentLang}`);
        if (text) {
            if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                el.placeholder = text;
            } else {
                el.textContent = text;
            }
        }
    });
    
    localStorage.setItem('vmstart-lang', currentLang);
}

function copyInstall(btn) {
    const cmd = document.getElementById('install-cmd').textContent;
    navigator.clipboard.writeText(cmd).then(() => {
        btn.textContent = currentLang === 'zh' ? '已复制' : 'Copied';
        setTimeout(() => { btn.textContent = btn.getAttribute(`data-${currentLang}`); }, 1500);
    });
}

function toggleMobileMenu() {
    const navLinks = document.querySelector('.nav-links');
    if (navLinks) {
        navLinks.classList.toggle('active');
    }
}

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
        const href = this.getAttribute('href');
        if (href === '#') return;
        
        e.preventDefault();
        const target = document.querySelector(href);
        if (target) {
            const offset = 80;
            const top = target.getBoundingClientRect().top + window.pageYOffset - offset;
            window.scrollTo({ top, behavior: 'smooth' });
            
            // Close mobile menu
            const navLinks = document.querySelector('.nav-links');
            if (navLinks) navLinks.classList.remove('active');
        }
    });
});

// Navbar scroll effect
let lastScroll = 0;
window.addEventListener('scroll', () => {
    const navbar = document.querySelector('.navbar');
    if (!navbar) return;
    
    const currentScroll = window.pageYOffset;
    
    if (currentScroll > 100) {
        navbar.style.background = 'rgba(13, 13, 15, 0.95)';
    } else {
        navbar.style.background = 'rgba(13, 13, 15, 0.85)';
    }
    
    lastScroll = currentScroll;
});

// Intersection Observer for animations
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, observerOptions);

document.querySelectorAll('.feature-card, .engine-card, .download-card, .doc-card').forEach(el => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(20px)';
    el.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
    observer.observe(el);
});

// Init
document.addEventListener('DOMContentLoaded', () => {
    const saved = localStorage.getItem('vmstart-lang');
    if (saved) {
        currentLang = saved;
    }
    applyLang();
});
