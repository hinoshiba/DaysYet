(() => {
  const header = document.querySelector('.site-header');
  const toggle = header?.querySelector('.nav-toggle');
  if (!toggle) return;

  const compact = window.matchMedia('(max-width: 1120px)');
  const setMenuOpen = (open) => {
    const isOpen = compact.matches && open;
    header.dataset.menuOpen = String(isOpen);
    toggle.setAttribute('aria-expanded', String(isOpen));
  };

  toggle.addEventListener('click', () => {
    setMenuOpen(header.dataset.menuOpen !== 'true');
    if (header.dataset.menuOpen === 'true') header.querySelector('.site-navigation a')?.focus();
  });
  header.addEventListener('click', (event) => {
    if (event.target.closest('a')) setMenuOpen(false);
  });
  header.addEventListener('focusout', (event) => {
    if (!header.contains(event.relatedTarget)) setMenuOpen(false);
  });
  document.addEventListener('click', (event) => {
    if (!header.contains(event.target)) setMenuOpen(false);
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && header.dataset.menuOpen === 'true') {
      setMenuOpen(false);
      toggle.focus();
      event.preventDefault();
    }
  });
  compact.addEventListener('change', () => setMenuOpen(false));
  setMenuOpen(false);
  document.documentElement.classList.add('has-js');
})();

(() => {
  const languageSwitch = document.querySelector('[data-language-base]');
  if (!languageSwitch) return;
  const syncLanguageLink = () => {
    languageSwitch.setAttribute('href', `${languageSwitch.dataset.languageBase}${window.location.hash}`);
  };
  window.addEventListener('hashchange', syncLanguageLink);
  syncLanguageLink();
})();

(() => {
  const preview = document.querySelector('[data-mac-preview]');
  const desktop = document.querySelector('[data-mac-desktop]');
  if (!preview || !desktop) return;

  const contour = preview.querySelector('[data-mac-contour]');
  const detail = preview.querySelector('[data-mac-detail]');
  const detailContent = preview.querySelector('[data-mac-detail-content]');
  const name = preview.querySelector('[data-mac-name]');
  const days = preview.querySelector('[data-mac-days]');
  const hours = preview.querySelector('[data-mac-hours]');
  const percentage = preview.querySelector('[data-mac-percentage]');
  const bar = preview.querySelector('[data-mac-progress]');
  const metricButtons = [...preview.querySelectorAll('[data-mac-metric]')];
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const scale = 1.5;
  let selected = 0;
  let selectionPosition = 0;
  let selectionFrame = 0;
  let expanded = false;
  let hovered = false;
  let hoverSuppressed = false;
  let progress = 0;
  let frame = 0;
  let showTimer = 0;
  let hideTimer = 0;
  let contentTimer = 0;
  let sidePosition = 0.5;
  let drag = null;
  let suppressClickUntil = 0;

  // The side contour follows the selected ring as the detail panel expands.
  class SideCurve {
    constructor(start, control1, control2, end) {
      this.start = start;
      this.control1 = control1;
      this.control2 = control2;
      this.end = end;
    }

    split(t) {
      const mix = (a, b) => a.map((value, index) => value + (b[index] - value) * t);
      const a = mix(this.start, this.control1);
      const b = mix(this.control1, this.control2);
      const c = mix(this.control2, this.end);
      const d = mix(a, b);
      const e = mix(b, c);
      const point = mix(d, e);
      return [new SideCurve(this.start, a, d, point), new SideCurve(point, e, c, this.end)];
    }

    position(t) {
      const [left, right] = this.split(t);
      const point = left.end;
      const tangent = t < 1 ? right.control1.map((value, index) => value - point[index])
        : point.map((value, index) => value - left.control2[index]);
      return { point, tangent };
    }

    parameter(y) {
      if (y <= this.start[1]) return 0;
      if (y >= this.end[1]) return 1;
      let lower = 0;
      let upper = 1;
      for (let step = 0; step < 36; step++) {
        const middle = (lower + upper) / 2;
        if (this.position(middle).point[1] < y) lower = middle;
        else upper = middle;
      }
      return (lower + upper) / 2;
    }

    portion(lower, upper) {
      const prefix = this.split(upper)[0];
      return lower > 0 && upper > 0 ? prefix.split(lower / upper)[1] : prefix;
    }

    static tangentControl(start, direction, length, maxHorizontal) {
      const magnitude = Math.hypot(...direction);
      if (magnitude === 0) return start;
      const unit = direction.map(value => value / magnitude);
      const distance = unit[0] > 0 ? Math.min(length, Math.max(maxHorizontal, 0) / unit[0]) : length;
      return start.map((value, index) => value + unit[index] * distance);
    }
  }

  const sideRail = [
    new SideCurve([0, 0], [0, 15.08], [12, 18.56], [28.98, 18.56]),
    new SideCurve([29, 18.56], [42, 18.56], [46, 26.97], [46, 40.6]),
    new SideCurve([46, 40.6], [46, 106], [46, 106], [46, 171.4]),
    new SideCurve([46, 171.4], [46, 185.03], [42, 193.44], [29, 193.44]),
    new SideCurve([28.98, 193.44], [12, 193.44], [0, 196.92], [0, 212])
  ];

  const draw = () => {
    const commands = ['M204 0'];
    const anchor = point => `${204 - point[0]} ${point[1]}`;
    const line = point => commands.push(`L${anchor(point)}`);
    const curve = (control1, control2, end) => commands.push(`C${anchor(control1)} ${anchor(control2)} ${anchor(end)}`);
    const railPosition = y => {
      const segment = sideRail.find(item => item.end[1] >= y) || sideRail[sideRail.length - 1];
      return segment.position(segment.parameter(y));
    };
    const appendRail = (lower, upper) => {
      sideRail.forEach(item => {
        if (item.end[1] <= lower || item.start[1] >= upper) return;
        const segment = item.portion(item.parameter(Math.max(lower, item.start[1])), item.parameter(Math.min(upper, item.end[1])));
        line(segment.start);
        curve(segment.control1, segment.control2, segment.end);
      });
    };

    if (progress > 0) {
      const width = 46 + 158 * progress;
      const center = 56 + 50 * selectionPosition;
      const top = center - 40 * progress;
      const bottom = center + 40 * progress;
      const join = 14 * progress;
      const corner = 26 * progress;
      const upper = railPosition(top - join);
      const lower = railPosition(bottom + join);
      const upperDepth = railPosition(top).point[0] + join;
      const lowerDepth = railPosition(bottom).point[0] + join;
      appendRail(0, top - join);
      const upperControl2 = [upperDepth - 9 * progress, top];
      const upperControl1 = SideCurve.tangentControl(upper.point, upper.tangent, 9 * progress, upperControl2[0] - upper.point[0]);
      curve(upperControl1, upperControl2, [upperDepth, top]);
      line([width - corner, top]);
      curve([width - 9 * progress, top], [width, top + 9 * progress], [width, top + corner]);
      line([width, bottom - corner]);
      curve([width, bottom - 9 * progress], [width - 9 * progress, bottom], [width - corner, bottom]);
      line([lowerDepth, bottom]);
      const lowerControl1 = [lowerDepth - 9 * progress, bottom];
      const lowerControl2 = SideCurve.tangentControl(lower.point, lower.tangent.map(value => -value), 9 * progress, lowerControl1[0] - lower.point[0]);
      curve(lowerControl1, lowerControl2, lower.point);
      appendRail(bottom + join, 212);
    } else appendRail(0, 212);

    commands.push('Z');
    contour.setAttribute('d', commands.join(' '));
    preview.style.setProperty('--side-detail-top', `${30 + 50 * selectionPosition}px`);
  };

  const sideBounds = () => {
    const halfHeight = 106 * scale;
    const lower = 44 + halfHeight;
    const upper = Math.max(lower, desktop.clientHeight - 12 - halfHeight);
    return { lower, travel: upper - lower };
  };
  const positionSide = () => {
    const bounds = sideBounds();
    preview.style.setProperty('--side-center', `${bounds.lower + bounds.travel * sidePosition}px`);
  };

  const animate = () => {
    cancelAnimationFrame(frame);
    const fromProgress = progress;
    const toProgress = expanded ? 1 : 0;
    if (reducedMotion.matches || fromProgress === toProgress) {
      progress = toProgress;
      draw();
      return;
    }
    const duration = expanded ? 240 : 180;
    const start = performance.now();
    const tick = (now) => {
      const time = Math.min(1, (now - start) / duration);
      progress = fromProgress + (toProgress - fromProgress) * (1 - Math.pow(1 - time, 3));
      draw();
      if (time < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
  };

  const followSelection = (animated = false) => {
    cancelAnimationFrame(selectionFrame);
    const fromPosition = selectionPosition;
    if (!animated || reducedMotion.matches || fromPosition === selected) {
      selectionPosition = selected;
      draw();
      return;
    }
    const toPosition = selected;
    const start = performance.now();
    const tick = (now) => {
      const time = Math.min(1, (now - start) / 180);
      selectionPosition = fromPosition + (toPosition - fromPosition) * (1 - Math.pow(1 - time, 3));
      draw();
      if (time < 1) selectionFrame = requestAnimationFrame(tick);
    };
    selectionFrame = requestAnimationFrame(tick);
  };

  const renderContent = () => {
    const metric = metricButtons[selected];
    name.textContent = metric.dataset.name;
    days.textContent = metric.dataset.days;
    hours.textContent = metric.dataset.hours;
    percentage.textContent = `${metric.dataset.percentage}%`;
    detail.style.setProperty('--detail-accent', metric.dataset.color);
    detail.style.setProperty('--detail-progress', `${metric.dataset.percentage}%`);
    bar.setAttribute('aria-valuenow', metric.dataset.percentage);
    detailContent.dataset.changing = 'false';
  };
  const update = (changeContent = false, changeSurface = true) => {
    preview.dataset.expanded = String(expanded);
    clearTimeout(contentTimer);
    if (changeContent && !reducedMotion.matches) {
      detailContent.dataset.changing = 'true';
      contentTimer = setTimeout(renderContent, 60);
    } else renderContent();
    detail.setAttribute('aria-hidden', String(!expanded));
    metricButtons.forEach((button, index) => {
      const active = expanded && selected === index;
      button.dataset.active = String(active);
      button.setAttribute('aria-expanded', String(active));
    });
    if (changeSurface) animate();
  };

  const cancelTimers = () => {
    clearTimeout(showTimer);
    clearTimeout(hideTimer);
  };
  const close = (explicit = false) => {
    cancelTimers();
    hoverSuppressed = explicit && hovered;
    expanded = false;
    update();
  };
  const select = (index) => {
    cancelTimers();
    const changeContent = expanded && selected !== index;
    const changeSurface = !expanded;
    selected = index;
    if (changeContent || changeSurface) followSelection(changeContent);
    expanded = true;
    update(changeContent, changeSurface);
  };

  metricButtons.forEach((button, index) => {
    button.addEventListener('pointerenter', (event) => {
      if (drag || event.pointerType === 'touch') return;
      cancelTimers();
      if (!hoverSuppressed) showTimer = setTimeout(() => select(index), expanded ? 80 : 160);
    });
    button.addEventListener('focus', () => {
      if (!drag?.moved) select(index);
    });
    button.addEventListener('click', () => {
      hoverSuppressed = false;
      select(index);
    });
  });

  preview.addEventListener('pointerdown', (event) => {
    if (event.button !== 0 || !event.isPrimary) return;
    cancelTimers();
    drag = { id: event.pointerId, startY: event.clientY, startPosition: sidePosition, moved: false };
  });
  window.addEventListener('pointermove', (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    const delta = event.clientY - drag.startY;
    if (!drag.moved && Math.abs(delta) < 5) return;
    if (!drag.moved) preview.setPointerCapture(event.pointerId);
    drag.moved = true;
    preview.dataset.dragging = 'true';
    cancelTimers();
    const bounds = sideBounds();
    sidePosition = bounds.travel > 0 ? Math.max(0, Math.min(1, drag.startPosition + delta / bounds.travel)) : 0.5;
    positionSide();
    event.preventDefault();
  }, { passive: false });
  const finishDrag = (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    if (drag.moved) suppressClickUntil = performance.now() + 500;
    const pointerId = drag.id;
    drag = null;
    preview.dataset.dragging = 'false';
    if (preview.hasPointerCapture(pointerId)) preview.releasePointerCapture(pointerId);
    const target = document.elementFromPoint(event.clientX, event.clientY);
    hovered = event.pointerType !== 'touch' && Boolean(target && preview.contains(target));
    if (!hovered) hoverSuppressed = false;
    if (!hovered && !preview.contains(document.activeElement)) hideTimer = setTimeout(close, 180);
  };
  window.addEventListener('pointerup', finishDrag);
  window.addEventListener('pointercancel', finishDrag);
  preview.addEventListener('lostpointercapture', finishDrag);
  preview.addEventListener('click', (event) => {
    if (event.detail !== 0 && performance.now() < suppressClickUntil) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);
  preview.addEventListener('pointerenter', (event) => {
    if (!drag && event.pointerType !== 'touch') {
      hovered = true;
      clearTimeout(hideTimer);
    }
  });
  preview.addEventListener('pointerleave', () => {
    if (drag) return;
    hovered = false;
    hoverSuppressed = false;
    clearTimeout(showTimer);
    if (!preview.contains(document.activeElement)) hideTimer = setTimeout(close, 180);
  });
  preview.addEventListener('focusout', (event) => {
    if (!preview.contains(event.relatedTarget) && !hovered) close();
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && expanded) {
      close(true);
      event.preventDefault();
    }
  });
  document.addEventListener('pointerdown', (event) => {
    if (!preview.contains(event.target)) close();
  });
  reducedMotion.addEventListener('change', () => {
    followSelection();
    update();
  });
  new ResizeObserver(positionSide).observe(desktop);
  preview.style.setProperty('--demo-scale', String(scale));
  positionSide();
  update();
})();
