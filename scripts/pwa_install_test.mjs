// Platform-neutral install UX contract. Run via GitHub-hosted PWA workflow.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

const source = readFileSync(new URL('../web/install_prompt.js', import.meta.url), 'utf8');

function environment({agent = 'Mozilla/5.0 (Linux; Android 16)', standalone = false, lastDismissal} = {}) {
  const events = new Map();
  const timers = [];
  const nodes = [];
  const data = new Map();
  if (lastDismissal !== undefined) {
    data.set('little-rest-install-guide-dismissed', String(lastDismissal));
  }
  class Node {
    constructor(tag) {
      this.tag = tag;
      this.children = [];
      this.attributes = {};
      this.listeners = new Map();
      this.className = '';
      this.textContent = '';
      this.removed = false;
      this.parent = null;
    }
    append(...children) { for (const child of children) this.appendChild(child); }
    appendChild(child) {
      this.children.push(child);
      child.parent = this;
      return child;
    }
    setAttribute(key, value) { this.attributes[key] = value; }
    addEventListener(type, handler) { this.listeners.set(type, handler); }
    dispatch(type, event = {}) { return this.listeners.get(type)?.(event); }
    remove() { this.removed = true; }
    querySelector(selector) {
      if (!this.queries) this.queries = new Map();
      if (!this.queries.has(selector)) this.queries.set(selector, new Node(selector));
      return this.queries.get(selector);
    }
    focus() {}
  }
  const body = new Node('body');
  const window = {
    navigator: null,
    matchMedia: () => ({matches: standalone}),
    addEventListener(type, listener) {
      if (!events.has(type)) events.set(type, []);
      events.get(type).push(listener);
    },
    dispatch(type, event = {}) {
      for (const listener of events.get(type) || []) listener(event);
    },
  };
  const navigator = {
    userAgent: agent,
    platform: 'Linux arm',
    maxTouchPoints: 5,
    standalone: false,
  };
  window.navigator = navigator;
  const document = {body, createElement: tag => {
    const node = new Node(tag);
    nodes.push(node);
    return node;
  }};
  vm.runInNewContext(source, {
    window, document, navigator,
    setTimeout: callback => { timers.push(callback); },
    localStorage: {
      getItem: key => data.get(key) ?? null,
      setItem: (key, value) => data.set(key, value),
    },
    Date, Promise,
  }, {timeout: 1000});
  return {
    window, body, nodes, data, timers,
    banner: () => body.children.find(node => node.className === 'lr-install-banner' && !node.removed),
    dialog: () => body.children.find(node => node.className === 'lr-install-backdrop' && !node.removed),
    load() { window.dispatch('load'); for (const callback of timers) callback(); },
  };
}

test('Android browser offers a dismissible manual path without a Chromium prompt', () => {
  const ui = environment();
  ui.load();
  assert.ok(ui.banner());
  const buttons = ui.banner().children;
  assert.equal(buttons[1].textContent, 'Install');
  buttons[1].dispatch('click');
  assert.ok(ui.dialog());
  assert.match(ui.dialog().querySelector('#lr-install-description').textContent, /Chrome.*Add to Home screen.*Install/);
  ui.dialog().querySelector('.lr-install-done').dispatch('click');
  assert.equal(ui.banner(), undefined);
  assert.equal(ui.dialog(), undefined);
  assert.ok(Number(ui.data.get('little-rest-install-guide-dismissed')) > 0);
});

test('iPhone browser uses Share menu, not an invented native prompt', () => {
  const ui = environment({agent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 27_0)'});
  ui.load();
  assert.ok(ui.banner());
  ui.banner().children[1].dispatch('click');
  assert.match(ui.dialog().querySelector('#lr-install-description').textContent, /Safari.*Share.*Add to Home Screen/);
});

test('Stand-alone PWA never overlays sleep actions', () => {
  const ui = environment({standalone: true});
  ui.load();
  assert.equal(ui.banner(), undefined);
  assert.equal(ui.dialog(), undefined);
});

test('Chromium install prompt fires only on a direct Install click', async () => {
  const ui = environment();
  let prevented = 0;
  let prompted = 0;
  ui.window.dispatch('beforeinstallprompt', {
    preventDefault() { prevented++; },
    async prompt() { prompted++; },
    userChoice: Promise.resolve({outcome: 'accepted'}),
  });
  assert.equal(prevented, 1);
  assert.equal(prompted, 0);
  assert.ok(ui.banner());
  await ui.banner().children[1].dispatch('click');
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(prompted, 1);
  ui.window.dispatch('appinstalled');
  assert.equal(ui.banner(), undefined);
});

test('A previous dismissal is honored across browser page reloads', () => {
  const ui = environment({lastDismissal: Date.now()});
  ui.load();
  assert.equal(ui.banner(), undefined);
});
