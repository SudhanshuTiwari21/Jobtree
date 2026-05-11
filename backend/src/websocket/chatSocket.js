import { WebSocketServer } from 'ws';
import { URL } from 'url';
import authService from '../services/authService.js';
import chatService from '../services/chatService.js';
import logger from '../utils/logger.js';

/** applicationId -> Set<WebSocket> */
const rooms = new Map();

function joinRoom(ws, applicationId) {
  if (!rooms.has(applicationId)) {
    rooms.set(applicationId, new Set());
  }
  rooms.get(applicationId).add(ws);
  ws.chatApplicationId = applicationId;
}

function leaveRoom(ws) {
  const id = ws.chatApplicationId;
  if (!id) return;
  const set = rooms.get(id);
  if (set) {
    set.delete(ws);
    if (set.size === 0) rooms.delete(id);
  }
  ws.chatApplicationId = undefined;
}

function broadcast(applicationId, payload) {
  const set = rooms.get(applicationId);
  if (!set) return;
  const raw = JSON.stringify(payload);
  for (const client of set) {
    if (client.readyState === 1) {
      try {
        client.send(raw);
      } catch (e) {
        logger.warn('Chat broadcast send failed:', e.message);
      }
    }
  }
}

function parseUserFromToken(token) {
  if (!token) return null;
  const decoded = authService.verifyToken(token);
  if (!decoded || decoded.type !== 'access') return null;
  if (decoded.role === 'salon') {
    return { userType: 'owner', userId: decoded.salonId };
  }
  if (decoded.role === 'seeker') {
    return { userType: 'seeker', userId: decoded.seekerId };
  }
  return null;
}

/**
 * Attach WebSocket server for path /ws/chat?token=JWT
 * Protocol: JSON messages { type: 'join', applicationId }, { type: 'message', applicationId, body }
 */
export function attachChatSocketServer(httpServer) {
  const wss = new WebSocketServer({ noServer: true });

  httpServer.on('upgrade', (request, socket, head) => {
    try {
      const host = request.headers.host || 'localhost';
      const pathname = new URL(request.url, `http://${host}`).pathname;
      if (pathname !== '/ws/chat') {
        socket.destroy();
        return;
      }
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    } catch (e) {
      logger.warn('WebSocket upgrade error:', e.message);
      socket.destroy();
    }
  });

  wss.on('connection', (ws, request) => {
    const host = request.headers.host || 'localhost';
    const url = new URL(request.url, `http://${host}`);
    const token = url.searchParams.get('token');
    const user = parseUserFromToken(token);
    if (!user) {
      ws.close(4001, 'Unauthorized');
      return;
    }
    ws.userType = user.userType;
    ws.userId = user.userId;

    ws.on('message', async (data) => {
      let msg;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }
      if (!msg || typeof msg !== 'object') return;

      try {
        if (msg.type === 'join' && msg.applicationId) {
          await chatService.assertParticipant(msg.applicationId, ws.userType, ws.userId);
          leaveRoom(ws);
          joinRoom(ws, msg.applicationId);
          ws.send(JSON.stringify({ type: 'joined', applicationId: msg.applicationId }));
          return;
        }

        if (msg.type === 'message' && msg.applicationId && msg.body != null) {
          await chatService.assertParticipant(msg.applicationId, ws.userType, ws.userId);
          const senderRole = ws.userType === 'owner' ? 'owner' : 'seeker';
          const saved = await chatService.insertMessage(msg.applicationId, senderRole, msg.body);
          const out = { type: 'message', message: saved };
          broadcast(msg.applicationId, out);
          return;
        }
      } catch (e) {
        const code = e.statusCode || 500;
        ws.send(JSON.stringify({
          type: 'error',
          code,
          message: e.message || 'Failed',
        }));
      }
    });

    ws.on('close', () => {
      leaveRoom(ws);
    });

    ws.on('error', () => {
      leaveRoom(ws);
    });

    ws.send(JSON.stringify({ type: 'ready' }));
  });

  logger.info('WebSocket chat listening at /ws/chat');
}
