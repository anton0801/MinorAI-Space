/* Minor Ai: icon helper for the reference previews. Icons approximate SF Symbols; the app uses the real SF Symbols named in each component README. */
(function () {
  var S = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
  var F = 'fill="currentColor" stroke="none"';
  var P = {
    'arrow.up': '<path ' + S + ' stroke-width="2.8" d="M12 19V5M5.5 11.5 12 5l6.5 6.5"/>',
    'plus': '<path ' + S + ' stroke-width="2.8" d="M12 5v14M5 12h14"/>',
    'photo': '<g ' + S + '><rect x="3" y="5" width="18" height="14" rx="3"/><circle cx="9" cy="10" r="1.6"/><path d="m4 17 5-5 4 4 2.5-2.5L20 17"/></g>',
    'house.fill': '<path ' + F + ' d="M3.5 10.6 12 3.5l8.5 7.1V20a1 1 0 0 1-1 1H15v-6H9v6H4.5a1 1 0 0 1-1-1z"/>',
    'gear': '<g ' + S + '><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="6.5"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/></g>',
    'square.and.pencil': '<path ' + S + ' d="M11 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5M17.5 3.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z"/>',
    'trash': '<path ' + S + ' d="M4 7h16M9 7V4h6v3M6.5 7l1 13h9l1-13M10 11v6M14 11v6"/>',
    'message': '<path ' + S + ' d="M12 4c4.7 0 8.5 3.1 8.5 7s-3.8 7-8.5 7c-1 0-2-.1-2.9-.4L4.5 20l1.3-3.6C4.3 15 3.5 13.1 3.5 11c0-3.9 3.8-7 8.5-7z"/>',
    'star.fill': '<path ' + F + ' d="m12 3 2.7 6 6.3.5-4.8 4.1 1.5 6.4-5.7-3.4L6.3 20l1.5-6.4L3 9.5 9.3 9z"/>',
    'paintbrush.fill': '<path ' + F + ' d="M19.3 2.8a1.5 1.5 0 0 1 2 2L13 14.2 9.8 11zM8.6 12.3l3.1 3.1c.1 2.6-1.6 5.6-7.7 5.6 1.4-1.3 1-3 1.5-4.6.6-2.3 1.7-3.8 3.1-4.1z"/>',
    'key.fill': '<g ' + S + '><circle cx="8" cy="15" r="4.2"/><path d="m11 12 9-9M16.5 6.5l2.2 2.2M14 9l2 2"/></g>',
    'chevron.right': '<path ' + S + ' d="m9 5 7 7-7 7"/>',
    'xmark': '<path ' + S + ' stroke-width="2.8" d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
    'info.circle': '<g ' + S + '><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.6v.1"/></g>',
    'checkmark': '<path ' + S + ' d="m5 12.5 4.5 4.5L19 7"/>',
    'sparkles': '<path ' + F + ' d="m11 3 1.9 5.1L18 10l-5.1 1.9L11 17l-1.9-5.1L4 10l5.1-1.9zM18.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/>',
    'link': '<path ' + S + ' d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    'doc.text': '<path ' + S + ' d="M6 3h8l4 4v14H6zM14 3v4h4M9 12h6M9 16h6"/>',
    'play.rectangle': '<g><rect ' + S + ' x="2.5" y="5" width="19" height="14" rx="4"/><path ' + F + ' d="m10 9 5 3-5 3z"/></g>',
    'waveform': '<path ' + S + ' d="M4 10v4M8 7v10M12 4v16M16 8v8M20 11v2"/>',
    'bubble.left': '<path ' + S + ' d="M5 4h12a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-6l-4 3.5V15H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"/>',
    'textformat': '<path ' + S + ' d="m3 18 5-12 5 12M4.8 14h6.4M18 11.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM20.5 11v7"/>',
    'square.and.arrow.up': '<path ' + S + ' d="M12 3v12M8 7l4-4 4 4M6 11H5v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8h-1"/>',
    'ellipsis': '<g ' + F + '><circle cx="5.5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="18.5" cy="12" r="1.8"/></g>',
    'tree': '<g ' + S + '><rect x="2.5" y="10" width="5" height="4" rx="1"/><rect x="15.5" y="3.5" width="6" height="4" rx="1"/><rect x="15.5" y="16.5" width="6" height="4" rx="1"/><path d="M7.5 12h4M11.5 5.5v13M11.5 5.5h4M11.5 18.5h4"/></g>',
    'minus.circle': '<g ' + S + '><circle cx="12" cy="12" r="9"/><path d="M8 12h8"/></g>',
    'pin': '<path ' + S + ' d="M9 3.5h6M10 3.5V10l-3 4h10l-3-4V3.5M12 14v6.5"/>',
    'pencil': '<path ' + S + ' d="m4 20 1-4L16 5a2.1 2.1 0 0 1 3 3L8 19z"/>',
    'circle.lefthalf.filled': '<g><circle ' + S + ' cx="12" cy="12" r="8.5"/><path ' + F + ' d="M12 3.5a8.5 8.5 0 0 0 0 17z"/></g>',
    'arrow.uturn.backward': '<path ' + S + ' d="M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
    'list.bullet': '<g><path ' + S + ' d="M9 6h11M9 12h11M9 18h11"/><g ' + F + '><circle cx="4.5" cy="6" r="1.5"/><circle cx="4.5" cy="12" r="1.5"/><circle cx="4.5" cy="18" r="1.5"/></g></g>',
    'video': '<path ' + S + ' d="M3 8a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM16 10.5l5-3v9l-5-3"/>',
    'brain': '<path ' + S + ' d="M12 5a3 3 0 0 0-5.6 1.4A3 3 0 0 0 4 11a3 3 0 0 0 1.4 5A3 3 0 0 0 10 19h2zM12 5a3 3 0 0 1 5.6 1.4A3 3 0 0 1 20 11a3 3 0 0 1-1.4 5A3 3 0 0 1 14 19h-2zM12 5v14"/>',
    'map': '<path ' + S + ' d="m3 6 6-2 6 2 6-2v14l-6 2-6-2-6 2zM9 4v14M15 6v14"/>',
    'slider.horizontal.3': '<g><path ' + S + ' d="M4 6h16M4 12h16M4 18h16"/><g ' + F + '><circle cx="8" cy="6" r="2.3"/><circle cx="15" cy="12" r="2.3"/><circle cx="10" cy="18" r="2.3"/></g></g>',
    'scope': '<g ' + S + '><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/></g>',
    'mic': '<g ' + S + '><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></g>',
    'lock.fill': '<g><rect ' + F + ' x="5" y="11" width="14" height="10" rx="2"/><path ' + S + ' d="M8 11V8a4 4 0 0 1 8 0v3"/></g>',
    'text.alignleft': '<path ' + S + ' d="M4 6h16M4 10h10M4 14h16M4 18h10"/>',
    'doc.on.doc': '<path ' + S + ' d="M9 8h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2zM16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h1"/>',
    'magnifyingglass': '<path ' + S + ' d="M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM20 20l-4.8-4.8"/>',
    'globe': '<g ' + S + '><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z"/></g>',
    'rectangle.portrait.and.arrow.right': '<path ' + S + ' d="M14 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h8M10 12h10M17 8.5l3.5 3.5-3.5 3.5"/>',
    'gearshape.fill': '<g ' + S + ' stroke-width="2.6"><circle cx="12" cy="12" r="5" stroke-width="4"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/></g>',
    'arrow.triangle.branch': '<path ' + S + ' d="M6 4v8a4 4 0 0 0 4 4h8M14 12l4 4-4 4M6 4l-2.5 2.5M6 4l2.5 2.5"/>'
  };
  function svg(name) {
    var body = P[name];
    if (!body) return '';
    return '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">' + body + '</svg>';
  }
  function hydrate(root) {
    var nodes = (root || document).querySelectorAll('[data-i]');
    for (var k = 0; k < nodes.length; k++) {
      var n = nodes[k];
      if (!n.firstChild) n.innerHTML = svg(n.getAttribute('data-i'));
    }
  }
  window.Minor = { icon: svg, hydrate: hydrate, names: Object.keys(P) };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { hydrate(); });
  else hydrate();
})();
