(function() {
    var CHARS = 'ﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘｱﾎﾃﾏｹﾒｴｶｷﾑﾕﾗｾﾈｽﾀﾇﾍ0123456789';
    var FONT_SIZE = 16;
    var STEP_MS = 100;
    var COLUMN_CHANCE = 0.008;
    var TRAIL_LENGTH = 12;
    var HEAD_ALPHA = 0.18;
    var TRAIL_START_ALPHA = 0.06;

    var canvas = document.createElement('canvas');
    canvas.id = '__minimark-matrix-rain';
    canvas.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;z-index:1;pointer-events:none;';
    document.body.appendChild(canvas);

    var ctx = canvas.getContext('2d');
    var columns = [];
    var intervalId = null;

    function makeColumn() {
        return { head: 0, active: false, chars: [] };
    }

    function resize() {
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
        var colCount = Math.floor(canvas.width / FONT_SIZE);
        while (columns.length < colCount) columns.push(makeColumn());
        while (columns.length > colCount) columns.pop();
    }

    function step() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.font = FONT_SIZE + 'px monospace';

        for (var i = 0; i < columns.length; i++) {
            var col = columns[i];

            if (!col.active) {
                if (Math.random() < COLUMN_CHANCE) {
                    col.active = true;
                    col.head = 0;
                    col.chars = [];
                } else {
                    continue;
                }
            }

            var ch = CHARS[Math.floor(Math.random() * CHARS.length)];
            col.chars.push(ch);
            if (col.chars.length > TRAIL_LENGTH) col.chars.shift();

            var x = i * FONT_SIZE;

            for (var j = 0; j < col.chars.length; j++) {
                var age = col.chars.length - 1 - j;
                var row = col.head - age;
                if (row < 0) continue;
                var y = row * FONT_SIZE;
                if (y > canvas.height) continue;

                var alpha = (age === 0) ? HEAD_ALPHA : TRAIL_START_ALPHA * (1 - age / TRAIL_LENGTH);
                if (alpha <= 0) continue;

                var r = (age === 0) ? 180 : 0;
                var g = 255;
                var b = (age === 0) ? 200 : 65;
                ctx.fillStyle = 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
                ctx.fillText(col.chars[j], x, y);
            }

            col.head++;

            if ((col.head - TRAIL_LENGTH) * FONT_SIZE > canvas.height && Math.random() > 0.975) {
                col.active = false;
            }
        }
    }

    function start() {
        resize();
        intervalId = setInterval(step, STEP_MS);
    }

    var reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!reducedMotion) {
        start();
        window.addEventListener('resize', resize);
    }

    window.__minimarkThemeCleanup = function() {
        if (intervalId) clearInterval(intervalId);
        window.removeEventListener('resize', resize);
        var el = document.getElementById('__minimark-matrix-rain');
        if (el) el.remove();
    };
})();
