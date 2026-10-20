import { test, expect } from '../../support/online/fixtures';
import { strictText } from '../../support/api';
import { portOf, rawHead } from '../../support/raw-http';

/*
 * OA-12 (novo na O4; MC-04 e MC-05): a página online e os seus arquivos
 * entram na lista fixa de estáticos; a página local ganha só o link
 * "Jogar online". Nada fora da lista continua sendo servido (o A-10 antigo
 * cobre /inexistente.js e afins).
 */

const FILES: Array<[string, string, string]> = [
  ['/online.html', 'text/html; charset=utf-8', 'data-testid="online-app"'],
  ['/online.js', 'text/javascript; charset=utf-8', '/api/rooms'],
  ['/online.css', 'text/css; charset=utf-8', '.online-'],
];

test('OA-12 [CAO-44, CAO-45] /online.html, /online.js e /online.css na lista fixa; link "Jogar online" na página local', async ({ request, baseURL }) => {
  for (const [path, type, marker] of FILES) {
    const res = await request.get(path);
    expect(res.status(), `GET ${path}`).toBe(200);
    expect(res.headers()['content-type'], `${path}: Content-Type`).toBe(type);
    expect(res.headers()['cache-control'], `${path}: Cache-Control`).toBe('no-cache');
    expect(await strictText(res), `conteúdo de ${path}`).toContain(marker);
    const head = await rawHead(portOf(baseURL), path);
    expect(head.statusLine, `HEAD ${path}`).toBe('HTTP/1.1 200 OK');
    expect(head.bodyBytes, `HEAD ${path} sem corpo`).toBe(0);
    const post = await request.post(path, { data: '{}' });
    expect(post.status(), `POST ${path}`).toBe(405);
    expect(post.headers()['allow']).toBe('GET, HEAD');
  }
  for (const path of ['/online.htm', '/online', '/online.html/', '/web/online.html', '/online.js.map']) {
    expect((await request.get(path)).status(), `GET ${path}`).toBe(404);
  }
  const html = await (await request.get('/online.html')).text();
  expect(html, 'a página online usa o mesmo style.css').toContain('href="/style.css"');
  expect(html).toContain('href="/online.css"');
  expect(html).toContain('src="/online.js"');

  const local = await (await request.get('/')).text();
  expect(local, 'a página local ganha o link "Jogar online"').toMatch(/<a [^>]*href="\/online\.html"[^>]*>Jogar online<\/a>/);
  expect(local, 'a página local continua com o próprio script').toContain('src="/app.js"');
});
