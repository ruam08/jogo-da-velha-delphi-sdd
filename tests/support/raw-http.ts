import * as net from 'node:net';

/**
 * Envia um HEAD pelo socket e lê a resposta crua até o servidor fechar a
 * conexão. Necessário porque clientes HTTP descartam o corpo de um HEAD:
 * só assim dá para provar que o servidor não enviou bytes de corpo.
 */
export function rawHead(port: number, path: string): Promise<{ statusLine: string; headers: string; bodyBytes: number }> {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    const chunks: Buffer[] = [];
    socket.setTimeout(5000, () => socket.destroy(new Error('tempo esgotado lendo a resposta do HEAD')));
    socket.on('connect', () => {
      socket.write(`HEAD ${path} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nConnection: close\r\n\r\n`);
    });
    socket.on('data', (chunk: Buffer | string) => chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, 'latin1')));
    socket.on('error', reject);
    socket.on('close', () => {
      const raw = Buffer.concat(chunks);
      const sep = raw.indexOf('\r\n\r\n');
      const headers = (sep < 0 ? raw : raw.subarray(0, sep)).toString('latin1');
      resolve({
        statusLine: headers.split('\r\n')[0] ?? '',
        headers,
        bodyBytes: sep < 0 ? -1 : raw.length - (sep + 4),
      });
    });
  });
}

/** Porta do servidor em teste, a partir da baseURL configurada. */
export function portOf(baseURL: string | undefined): number {
  return Number(new URL(baseURL ?? 'http://127.0.0.1:8765').port);
}
