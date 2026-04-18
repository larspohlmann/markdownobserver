(function() {
    var canvas = document.createElement('canvas');
    canvas.id = '__minimark-reef-caustics';
    canvas.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;z-index:1;pointer-events:none;mix-blend-mode:screen;';
    document.body.appendChild(canvas);

    var ctx = canvas.getContext('2d');
    var rafId = null;
    var t0 = performance.now();

    function resize() {
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
    }

    function frame(now) {
        var t = (now - t0) / 1000;
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        var blobs = [
            { x: 0.2 + 0.05 * Math.sin(t * 0.3), y: 0.25 + 0.03 * Math.cos(t * 0.4), r: 0.35, a: 0.16 },
            { x: 0.8 + 0.04 * Math.cos(t * 0.25), y: 0.75 + 0.04 * Math.sin(t * 0.35), r: 0.4,  a: 0.10 },
            { x: 0.6 + 0.06 * Math.sin(t * 0.2),  y: 0.5  + 0.03 * Math.cos(t * 0.3),  r: 0.28, a: 0.08 }
        ];

        for (var i = 0; i < blobs.length; i++) {
            var b = blobs[i];
            var cx = b.x * canvas.width, cy = b.y * canvas.height;
            var rad = b.r * Math.min(canvas.width, canvas.height);
            var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, rad);
            g.addColorStop(0, 'rgba(74,220,186,' + b.a + ')');
            g.addColorStop(1, 'rgba(74,220,186,0)');
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
        rafId = requestAnimationFrame(frame);
    }

    resize();
    window.addEventListener('resize', resize);
    var reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!reducedMotion) rafId = requestAnimationFrame(frame);

    window.__minimarkThemeCleanup = function() {
        if (rafId) cancelAnimationFrame(rafId);
        window.removeEventListener('resize', resize);
        var el = document.getElementById('__minimark-reef-caustics');
        if (el) el.remove();
    };
})();
