import * as net from 'node:net';

/*
 * Requisição HTTP por socket cru: permite cabeçalhos que um cliente HTTP
 * normal não deixa forjar (Host de outro site, dois Origin). Usada nos testes
 * de origem (OA-10, OV-05), para simular DNS rebinding.
 */

export interface RawResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export function rawRequest(port: number, method: string, path: string,
  headers: Array<[string, string]>, body = ''): Promise<RawResponse> {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    const chunks: Buffer[] = [];
    socket.setTimeout(5000, () => socket.destroy(new Error('tempo esgotado na requisição crua')));
    socket.on('connect', () => {
      let req = `${method} ${path} HTTP/1.1\r\n`;
      for (const [name, value] of headers) req += `${name}: ${value}\r\n`;
      const data = Buffer.from(body, 'utf8');
      if (method !== 'GET' && method !== 'HEAD') req += `Content-Length: ${data.length}\r\n`;
      req += 'Connection: close\r\n\r\n';
      socket.write(Buffer.concat([Buffer.from(req, 'latin1'), data]));
    });
    socket.on('data', (c: Buffer) => chunks.push(c));
    socket.on('error', reject);
    socket.on('close', () => {
      const raw = Buffer.concat(chunks);
      const sep = raw.indexOf('\r\n\r\n');
      const head = (sep < 0 ? raw : raw.subarray(0, sep)).toString('latin1');
      const lines = head.split('\r\n');
      const result: RawResponse = { status: Number(lines[0]?.split(' ')[1] ?? 0), headers: {}, body: '' };
      for (const line of lines.slice(1)) {
        const i = line.indexOf(':');
        if (i > 0) result.headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
      }
      result.body = sep < 0 ? '' : raw.subarray(sep + 4).toString('utf8');
      resolve(result);
    });
  });
}
