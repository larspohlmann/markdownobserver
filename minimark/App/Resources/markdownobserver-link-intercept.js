(function() {
    function isMarkdownHref(href) {
        if (!href) return false;
        var bare = href.split('#')[0].split('?')[0];
        var dot = bare.lastIndexOf('.');
        if (dot < 0) return false;
        var ext = bare.substring(dot + 1).toLowerCase();
        return ext === 'md' || ext === 'markdown' || ext === 'mdown';
    }
    document.addEventListener('click', function(e) {
        if (e.defaultPrevented) return;
        if (e.button !== 0) return;
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        var a = e.target.closest && e.target.closest('a');
        if (!a) return;
        var rawHref = a.getAttribute('href');
        if (!isMarkdownHref(rawHref)) return;
        var resolvedHref = a.href;
        if (!resolvedHref) return;
        e.preventDefault();
        e.stopPropagation();
        try {
            window.webkit.messageHandlers.minimarkLinkClick.postMessage({
                url: resolvedHref
            });
        } catch (err) {}
    }, true);
})();
