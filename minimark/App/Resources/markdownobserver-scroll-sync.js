(() => {
    if (window.__minimarkScrollSyncInstalled) {
        return;
    }
    window.__minimarkScrollSyncInstalled = true;
    window.__minimarkScrollSyncSuppressionToken = null;

    function activeScrollTarget() {
        const sourceEditor = document.querySelector('.minimark-source-editor');
        if (sourceEditor) {
            return {
                kind: 'element',
                element: sourceEditor,
                viewportHeight: sourceEditor.clientHeight || 0
            };
        }

        const element = document.scrollingElement || document.documentElement || document.body;
        if (!element) {
            return null;
        }

        return {
            kind: 'page',
            element,
            viewportHeight: window.innerHeight || element.clientHeight || 0
        };
    }

    function currentScrollPayload() {
        const target = activeScrollTarget();
        if (!target || !target.element) {
            return null;
        }

        const element = target.element;
        const maxY = Math.max(0, element.scrollHeight - target.viewportHeight);
        const rawOffsetY = target.kind === 'page'
            ? (window.scrollY || element.scrollTop || 0)
            : (element.scrollTop || 0);
        const offsetY = Math.max(0, Math.min(rawOffsetY, maxY));
        const progress = maxY > 0 ? Math.min(Math.max(offsetY / maxY, 0), 1) : 0;
        return {
            offsetY,
            maxY,
            progress,
            targetKind: target.kind,
            suppressionToken: window.__minimarkScrollSyncSuppressionToken
        };
    }

    let scheduledState = { value: false };
    function publishScrollState() {
        scheduledState.value = false;
        const payload = currentScrollPayload();
        if (!payload) {
            return;
        }

        try {
            window.webkit.messageHandlers.minimarkScrollSync.postMessage(payload);
        } catch (_) {}
    }

    function schedulePublish() {
        if (scheduledState.value) {
            return;
        }
        scheduledState.value = true;
        window.requestAnimationFrame(publishScrollState);
    }

    window.addEventListener('scroll', schedulePublish, { passive: true, capture: true });
    window.addEventListener('resize', schedulePublish, { passive: true });
    window.addEventListener('load', schedulePublish);
    const mutationObserver = new MutationObserver(schedulePublish);
    mutationObserver.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'style']
    });

    setTimeout(schedulePublish, 0);
})();
