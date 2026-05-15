import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'agent_app.db');

return openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT,
        summary TEXT,
        context_data TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT,
        role TEXT,
        content TEXT,
        created_at INTEGER,
        is_truncated INTEGER DEFAULT 0,
        partial_content TEXT,
        token_offset INTEGER DEFAULT 0,
        content_hash TEXT,
        message_version INTEGER DEFAULT 1,
        depends_on TEXT,
        stream_state TEXT DEFAULT "completed",
        image_base64 TEXT,
        thinking TEXT,
        file_name TEXT,
        file_type TEXT,
        mime_type TEXT,
        file_size INTEGER,
        extracted_text TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        name TEXT,
        content TEXT,
        embedding BLOB,
        created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE tool_calls (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        message_id TEXT,
        tool_name TEXT NOT NULL,
        input_summary TEXT,
        output_summary TEXT,
        success INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER,
        risk_score REAL,
        created_at INTEGER,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE music_history (
        id TEXT PRIMARY KEY,
        prompt TEXT NOT NULL,
        lyrics TEXT,
        model TEXT NOT NULL,
        local_path TEXT NOT NULL,
        duration INTEGER,
        bitrate INTEGER,
        is_instrumental INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE image_history (
        id TEXT PRIMARY KEY,
        prompt TEXT NOT NULL,
        model TEXT NOT NULL,
        ratio TEXT,
        images TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_history (
        id TEXT PRIMARY KEY,
        prompt TEXT NOT NULL,
        model TEXT NOT NULL,
        duration INTEGER,
        resolution TEXT,
        video_url TEXT,
        thumbnail_url TEXT,
        template_id TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS speech_history (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        voice_id TEXT NOT NULL,
        voice_name TEXT NOT NULL,
        model TEXT NOT NULL,
        speed REAL,
        audio_url TEXT,
        created_at INTEGER NOT NULL
      )
    ''');


    // 记忆系统 — memories + tasks 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY,
        memory_type TEXT NOT NULL DEFAULT 'semantic',
        content TEXT NOT NULL,
        content_hash TEXT,
        category TEXT DEFAULT 'static',
        key TEXT,
        entities TEXT DEFAULT '[]',
        linked_memory_ids TEXT DEFAULT '[]',
        confidence TEXT DEFAULT 'medium',
        source TEXT DEFAULT 'ai',
        source_detail TEXT DEFAULT '',
        status TEXT DEFAULT 'active',
        superseded_by TEXT,
        embedding TEXT,
        embedding_source TEXT DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        title TEXT DEFAULT '',
        description TEXT DEFAULT '',
        task_type TEXT DEFAULT 'scheduled',
        interval_seconds INTEGER DEFAULT 0,
        due_time INTEGER,
        status TEXT DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER,
        is_active INTEGER DEFAULT 1,
        timeout_seconds INTEGER DEFAULT 60,
        max_retries INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_memories_status ON memories(status)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)
    ''');

    // pause_checkpoints — 流式断点恢复
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pause_checkpoints (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        context_data TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // task_conversations — 定时任务会话记录
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_conversations (
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      )
    ''');

    // task_executions — 定时任务执行日志
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_executions (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        title TEXT,
        started_at INTEGER,
        finished_at INTEGER,
        duration_ms INTEGER,
        success INTEGER DEFAULT 0,
        retries INTEGER DEFAULT 0,
        note TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_task_executions_task ON task_executions(task_id)');

    // agent_traces — 代理执行追踪
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_traces (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        trace_data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_agent_traces_conv ON agent_traces(conversation_id)');

    // agent_errors — 代理错误日志
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_errors (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        message_id TEXT,
        category TEXT NOT NULL,
        error_message TEXT NOT NULL,
        stack_trace TEXT,
        recoverable INTEGER DEFAULT 0,
        was_retried INTEGER DEFAULT 0,
        retry_success INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_agent_errors_conv ON agent_errors(conversation_id)');

    // page_index — 文档索引
    await db.execute('''
      CREATE TABLE IF NOT EXISTS page_index (
        doc_id TEXT PRIMARY KEY,
        doc_name TEXT NOT NULL,
        doc_description TEXT,
        doc_type TEXT,
        page_count INTEGER,
        line_count INTEGER,
        structure_json TEXT,
        accuracy REAL,
        content_hash TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // trend_platforms — 热搜平台
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trend_platforms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // trend_news_items — 热搜新闻条目
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trend_news_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        platform_id TEXT NOT NULL,
        rank INTEGER,
        url TEXT,
        mobile_url TEXT,
        hot_value TEXT,
        extra TEXT,
        cover TEXT,
        first_crawl_time INTEGER,
        last_crawl_time INTEGER,
        crawl_count INTEGER DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_trend_news_platform ON trend_news_items(platform_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_trend_news_title ON trend_news_items(title)');

    // trend_crawl_records — 爬取批次记录
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trend_crawl_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        crawl_time INTEGER NOT NULL,
        news_count INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // trend_crawl_source_statuses — 各数据源爬取状态
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trend_crawl_source_statuses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER NOT NULL,
        platform_id TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // trend_rank_history — 热搜排名历史
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trend_rank_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        news_item_id INTEGER NOT NULL,
        rank INTEGER NOT NULL,
        crawl_time INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_trend_rank_news ON trend_rank_history(news_item_id)');

    // ai_filter_tags — AI 兴趣标签
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_filter_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tag TEXT NOT NULL,
        description TEXT,
        priority INTEGER DEFAULT 0,
        version INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_filter_tags_version ON ai_filter_tags(version)');

    // ai_filter_results — AI 新闻分类结果
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_filter_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        news_item_id INTEGER NOT NULL,
        tag_id INTEGER,
        relevance_score REAL DEFAULT 0.0,
        tag_version INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    // memory_embeddings — 嵌入向量缓存
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text_hash TEXT NOT NULL,
        text_preview TEXT,
        embedding BLOB,
        source TEXT DEFAULT 'api',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_embeddings_hash ON memory_embeddings(text_hash)');

    // ===== Notes (知识笔记) =====
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        tags TEXT DEFAULT '[]',
        aliases TEXT DEFAULT '[]',
        pinned INTEGER DEFAULT 0,
        folder TEXT DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL,
        target_id TEXT,
        target_title TEXT NOT NULL,
        display_text TEXT,
        FOREIGN KEY (source_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_note_links_source ON note_links(source_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_note_links_target ON note_links(target_id)');
    // FTS5 全文搜索
    try {
      await db.execute('CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(title, content, tags, content=notes, content_rowid=_rowid_)');
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: notes + note_templates
      try { await db.execute("ALTER TABLE notes ADD COLUMN pinned INTEGER DEFAULT 0"); } catch (_) {}
      try { await db.execute("ALTER TABLE notes ADD COLUMN folder TEXT DEFAULT ''"); } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS note_templates (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          content TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      // v2 → v3: missing tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS video_history (
          id TEXT PRIMARY KEY,
          prompt TEXT NOT NULL,
          model TEXT NOT NULL,
          duration INTEGER,
          resolution TEXT,
          video_url TEXT,
          thumbnail_url TEXT,
          template_id TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS speech_history (
          id TEXT PRIMARY KEY,
          text TEXT NOT NULL,
          voice_id TEXT NOT NULL,
          voice_name TEXT NOT NULL,
          model TEXT NOT NULL,
          speed REAL,
          audio_url TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      // v3 → v4: tasks timeout/max_retries columns
      try { await db.execute("ALTER TABLE tasks ADD COLUMN timeout_seconds INTEGER DEFAULT 60"); } catch (_) {}
      try { await db.execute("ALTER TABLE tasks ADD COLUMN max_retries INTEGER DEFAULT 1"); } catch (_) {}
    }
  }

  // Conversation CRUD
  Future<String> createConversation(String title, {String? id}) async {
    final db = await database;
    id ??= DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('conversations', {
      'id': id,
      'title': title,
      'summary': '',
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final db = await database;
    return db.query('conversations', orderBy: 'updated_at DESC');
  }

  Future<void> deleteConversation(String id) async {
    final db = await database;
    await db.delete('messages', where: 'conversation_id = ?', whereArgs: [id]);
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMessagesByConversation(String conversationId) async {
    final db = await database;
    await db.delete('messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
  }

  Future<void> updateConversationSummary(String conversationId, String summary) async {
    final db = await database;
    await db.update(
      'conversations',
      {'summary': summary, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }


  Future<String?> getConversationSummary(String conversationId) async {
    final db = await database;
    final result = await db.query(
      'conversations',
      columns: ['summary'],
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    return result.isNotEmpty ? result.first['summary'] as String? : null;
  }

  Future<void> updateConversationContext(String conversationId, Map<String, dynamic> contextData) async {
    final db = await database;
    await db.update(
      'conversations',
      {
        'context_data': contextData.isNotEmpty ? jsonEncode(contextData) : null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<Map<String, dynamic>?> getConversationContext(String conversationId) async {
    final db = await database;
    final result = await db.query(
      'conversations',
      columns: ['context_data'],
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    if (result.isEmpty || result.first['context_data'] == null) return null;
    try {
      return jsonDecode(result.first['context_data'] as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Message CRUD
  Future<String> addMessage(String conversationId, String role, String content, {
    String? id,
    String? imageBase64,
    String? thinking,
    String? fileName,
    String? fileType,
    String? mimeType,
    int? fileSize,
    String? extractedText,
  }) async {
    final db = await database;
    final msgId = id ?? DateTime.now().microsecondsSinceEpoch.toString();
    await db.insert('messages', {
      'id': msgId,
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'is_truncated': 0,
      'partial_content': null,
      'token_offset': 0,
      'content_hash': null,
      'message_version': 1,
      'depends_on': null,
      'stream_state': 'completed',
      'image_base64': imageBase64,
      'thinking': thinking,
      'file_name': fileName,
      'file_type': fileType,
      'mime_type': mimeType,
      'file_size': fileSize,
      'extracted_text': extractedText,
    });
    await db.update(
      'conversations',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    return msgId;
  }

  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    final db = await database;
    return db.query('messages', where: 'conversation_id = ?', whereArgs: [conversationId], orderBy: 'created_at ASC');
  }

  /// 回溯：删除指定消息及之后的所有消息（物理删除）
  Future<int> deleteMessagesFrom(String conversationId, String messageId) async {
    final db = await database;
    final results = await db.query('messages',
      where: 'id = ?', whereArgs: [messageId],
      columns: ['created_at']);
    if (results.isEmpty) return 0;
    final ts = results.first['created_at'] as int;
    return db.delete('messages',
      where: 'conversation_id = ? AND created_at >= ?',
      whereArgs: [conversationId, ts]);
  }

  Future<void> updatePartialMessage({
    required String messageId,
    String? conversationId,
    required String partialContent,
    required int tokenOffset,
    required bool isTruncated,
    required String streamState,
  }) async {
    final db = await database;
    final affected = await db.update(
      'messages',
      {
        'partial_content': partialContent,
        'token_offset': tokenOffset,
        'is_truncated': isTruncated ? 1 : 0,
        'stream_state': streamState,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    if (affected == 0 && conversationId != null) {
      await db.insert('messages', {
        'id': messageId,
        'conversation_id': conversationId,
        'role': 'assistant',
        'content': '',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'is_truncated': isTruncated ? 1 : 0,
        'partial_content': partialContent,
        'token_offset': tokenOffset,
        'stream_state': streamState,
        'message_version': 1,
      });
    }
  }

  Future<void> updateMessageDependsOn(String messageId, String? dependsOn) async {
    final db = await database;
    await db.update(
      'messages',
      {'depends_on': dependsOn},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageVersion(String messageId, int version) async {
    final db = await database;
    await db.update(
      'messages',
      {'message_version': version},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateConversationLastTruncated(String conversationId, String? messageId) async {
    final db = await database;
    await db.update(
      'conversations',
      {'last_truncated_id': messageId},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<List<Map<String, dynamic>>> getTruncatedMessages(String conversationId) async {
    final db = await database;
    return db.query(
      'messages',
      where: 'conversation_id = ? AND is_truncated = 1',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
    );
  }

  // ===== Tool Calls (v11) =====

  Future<void> insertToolCall({
    required String id,
    required String conversationId,
    String? messageId,
    required String toolName,
    String? inputSummary,
    String? outputSummary,
    required bool success,
    int? durationMs,
    double? riskScore,
  }) async {
    final db = await database;
    await db.insert('tool_calls', {
      'id': id,
      'conversation_id': conversationId,
      'message_id': messageId,
      'tool_name': toolName,
      'input_summary': inputSummary,
      'output_summary': outputSummary,
      'success': success ? 1 : 0,
      'duration_ms': durationMs,
      'risk_score': riskScore,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateToolCallEnd({
    required String id,
    required bool success,
    required String outputSummary,
    required int durationMs,
  }) async {
    final db = await database;
    await db.update(
      'tool_calls',
      {
        'success': success ? 1 : 0,
        'output_summary': outputSummary,
        'duration_ms': durationMs,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getToolCallsForConversation(
    String conversationId, {
    int limit = 100,
  }) async {
    final db = await database;
    return db.query(
      'tool_calls',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getToolCallsByTool(
    String toolName, {
    int limit = 100,
  }) async {
    final db = await database;
    return db.query(
      'tool_calls',
      where: 'tool_name = ?',
      whereArgs: [toolName],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>> getToolCallStats(String conversationId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as totalCalls,
        CAST(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) AS REAL) / COUNT(*) as successRate,
        AVG(duration_ms) as avgDurationMs,
        AVG(risk_score) as avgRiskScore
      FROM tool_calls
      WHERE conversation_id = ?
    ''', [conversationId]);
    if (result.isEmpty || result.first['totalCalls'] == 0) {
      return {'totalCalls': 0, 'successRate': 0.0, 'avgDurationMs': 0, 'avgRiskScore': 0.0};
    }
    return result.first;
  }

  Future<void> deleteToolCallsForConversation(String conversationId) async {
    final db = await database;
    await db.delete('tool_calls', where: 'conversation_id = ?', whereArgs: [conversationId]);
  }

  // ===== Music History (v12) =====

  Future<void> insertMusicHistory({
    required String id,
    required String prompt,
    String? lyrics,
    required String model,
    required String localPath,
    int? duration,
    int? bitrate,
    required bool isInstrumental,
  }) async {
    final db = await database;
    await db.insert('music_history', {
      'id': id,
      'prompt': prompt,
      'lyrics': lyrics,
      'model': model,
      'local_path': localPath,
      'duration': duration,
      'bitrate': bitrate,
      'is_instrumental': isInstrumental ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getMusicHistory({int limit = 50}) async {
    final db = await database;
    return db.query('music_history', orderBy: 'created_at DESC', limit: limit);
  }

  Future<void> updateMusicHistory(String id, {String? prompt, String? lyrics}) async {
    final db = await database;
    final values = <String, dynamic>{};
    if (prompt != null) values['prompt'] = prompt;
    if (lyrics != null) values['lyrics'] = lyrics;
    if (values.isNotEmpty) {
      await db.update('music_history', values, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteMusicHistory(String id) async {
    final db = await database;
    await db.delete('music_history', where: 'id = ?', whereArgs: [id]);
  }

  // ===== Image History (v13) =====

  Future<void> insertImageHistory({
    required String id,
    required String prompt,
    required String model,
    String? ratio,
    required String imagesJson,
  }) async {
    final db = await database;
    await db.insert('image_history', {
      'id': id,
      'prompt': prompt,
      'model': model,
      'ratio': ratio,
      'images': imagesJson,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getImageHistory({int limit = 50}) async {
    final db = await database;
    return db.query('image_history', orderBy: 'created_at DESC', limit: limit);
  }

  Future<void> deleteImageHistory(String id) async {
    final db = await database;
    await db.delete('image_history', where: 'id = ?', whereArgs: [id]);
  }

  // ===== Video History (v15) =====

  Future<void> insertVideoHistory({
    required String id,
    required String prompt,
    required String model,
    int? duration,
    String? resolution,
    String? videoUrl,
    String? thumbnailUrl,
    String? templateId,
  }) async {
    final db = await database;
    await db.insert('video_history', {
      'id': id,
      'prompt': prompt,
      'model': model,
      'duration': duration,
      'resolution': resolution,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'template_id': templateId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getVideoHistory({int limit = 50}) async {
    final db = await database;
    return db.query('video_history', orderBy: 'created_at DESC', limit: limit);
  }

  Future<void> deleteVideoHistory(String id) async {
    final db = await database;
    await db.delete('video_history', where: 'id = ?', whereArgs: [id]);
  }

  // ===== Speech History (v16) =====

  Future<void> insertSpeechHistory({
    required String id,
    required String text,
    required String voiceId,
    required String voiceName,
    required String model,
    required double speed,
    required String audioUrl,
  }) async {
    final db = await database;
    await db.insert('speech_history', {
      'id': id,
      'text': text,
      'voice_id': voiceId,
      'voice_name': voiceName,
      'model': model,
      'speed': speed,
      'audio_url': audioUrl,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getSpeechHistory({int limit = 50}) async {
    final db = await database;
    return db.query('speech_history', orderBy: 'created_at DESC', limit: limit);
  }

  Future<void> deleteSpeechHistory(String id) async {
    final db = await database;
    await db.delete('speech_history', where: 'id = ?', whereArgs: [id]);
  }

  // ===== Branches (v14) =====









  Future<void> updateMessageContent(String messageId, String newContent) async {
    final db = await database;
    await db.update(
      'messages',
      {'content': newContent, 'message_version': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // ===== Memory CRUD =====

  Future<List<Map<String, dynamic>>> getAllMemories({String? status}) async {
    final db = await database;
    if (status != null) {
      return db.query('memories', where: 'status = ?', whereArgs: [status]);
    }
    return db.query('memories');
  }

  Future<void> insertMemory(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('memories', row);
  }

  Future<void> updateMemory(String id, Map<String, dynamic> data) async {
    final db = await database;
    data['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await db.update('memories', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMemory(String id) async {
    final db = await database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchMemoriesFts(String query) async {
    final db = await database;
    // LIKE-based fallback (FTS5 virtual table requires complex setup).
    // Filters active memories where content or key contains the query.
    final like = '%$query%';
    return db.query(
      'memories',
      where: 'status = ? AND (content LIKE ? OR key LIKE ?)',
      whereArgs: ['active', like, like],
    );
  }

  // ===== Task CRUD =====

  Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await database;
    return db.query('tasks');
  }

  Future<void> insertTask(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('tasks', row);
  }

  Future<void> updateTask(String id, Map<String, dynamic> data) async {
    final db = await database;
    data['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await db.update('tasks', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  // ===== taskConversationId const =====
  static const String taskConversationId = '__task_conversation__';

  // ===== Task Conversation =====
  Future<void> ensureTaskConversation() async {
    final db = await database;
    final existing = await db.query('conversations', where: 'id = ?', whereArgs: [taskConversationId], limit: 1);
    if (existing.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('conversations', {
        'id': taskConversationId,
        'title': '定时任务',
        'summary': '',
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  Future<void> addTaskConversationMessage({required String role, required String content}) async {
    await addMessage(taskConversationId, role, content);
  }

  Future<List<Map<String, dynamic>>> getTaskConversationMessages({int limit = 20}) async {
    final db = await database;
    return db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [taskConversationId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  // ===== Task Executions =====
  Future<void> insertTaskExecution(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('task_executions', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      ...data,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ===== Pause Checkpoints =====
  Future<void> savePauseCheckpoint(String messageId, String contextData) async {
    final db = await database;
    await db.insert('pause_checkpoints', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'message_id': messageId,
      'context_data': contextData,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, dynamic>?> getPauseCheckpoint(String messageId) async {
    final db = await database;
    final result = await db.query(
      'pause_checkpoints',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  // ===== Stream Messages =====
  Future<void> finalizeStreamMessage({
    required String messageId,
    required String conversationId,
    required String content,
    String? thinking,
  }) async {
    final db = await database;
    final affected = await db.update(
      'messages',
      {
        'content': content,
        'thinking': thinking,
        'is_truncated': 0,
        'partial_content': null,
        'stream_state': 'completed',
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    if (affected == 0) {
      await db.insert('messages', {
        'id': messageId,
        'conversation_id': conversationId,
        'role': 'assistant',
        'content': content,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'is_truncated': 0,
        'partial_content': null,
        'token_offset': 0,
        'stream_state': 'completed',
        'message_version': 1,
        'thinking': thinking,
      });
    }
    // Touch conversation updated_at
    await db.update(
      'conversations',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<List<String>> fixInterruptedMessages() async {
    final db = await database;
    final result = await db.query(
      'messages',
      where: "stream_state IN ('streaming', 'paused', 'failed')",
    );
    final ids = result.map((m) => m['id'] as String).toList();
    for (final id in ids) {
      await db.update('messages', {'stream_state': 'completed'}, where: 'id = ?', whereArgs: [id]);
    }
    return ids;
  }

  Future<bool> hasInterruptedMessages(String conversationId) async {
    final db = await database;
    final result = await db.query(
      'messages',
      where: "conversation_id = ? AND stream_state IN ('streaming', 'paused', 'failed')",
      whereArgs: [conversationId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // ===== Agent Traces =====
  Future<void> insertAgentTrace({
    required String id,
    required String conversationId,
    required String traceData,
  }) async {
    final db = await database;
    await db.insert('agent_traces', {
      'id': id,
      'conversation_id': conversationId,
      'trace_data': traceData,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ===== Agent Errors =====
  Future<void> insertAgentError({
    required String id,
    required String conversationId,
    String? messageId,
    required String category,
    required String errorMessage,
    String? stackTrace,
    bool recoverable = false,
    bool wasRetried = false,
    bool retrySuccess = false,
  }) async {
    final db = await database;
    await db.insert('agent_errors', {
      'id': id,
      'conversation_id': conversationId,
      'message_id': messageId,
      'category': category,
      'error_message': errorMessage,
      'stack_trace': stackTrace,
      'recoverable': recoverable ? 1 : 0,
      'was_retried': wasRetried ? 1 : 0,
      'retry_success': retrySuccess ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getAgentErrors({String? conversationId, int limit = 50}) async {
    final db = await database;
    var where = '';
    final args = <dynamic>[];
    if (conversationId != null) {
      where = 'conversation_id = ?';
      args.add(conversationId);
    }
    return db.query(
      'agent_errors',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<Map<String, int>> getAgentErrorStats() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT category, COUNT(*) as cnt FROM agent_errors GROUP BY category',
    );
    final stats = <String, int>{};
    for (final row in result) {
      stats[row['category'] as String] = row['cnt'] as int;
    }
    return stats;
  }

  // ===== Page Index =====
  Future<void> insertPageIndex({
    required String docId,
    required String docName,
    String? docDescription,
    String? docType,
    int? pageCount,
    int? lineCount,
    required String structureJson,
    double accuracy = 0.0,
    String? contentHash,
  }) async {
    final db = await database;
    await db.insert('page_index', {
      'doc_id': docId,
      'doc_name': docName,
      'doc_description': docDescription,
      'doc_type': docType,
      'page_count': pageCount,
      'line_count': lineCount,
      'structure_json': structureJson,
      'accuracy': accuracy,
      'content_hash': contentHash,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getPageIndex(String docId) async {
    final db = await database;
    final result = await db.query('page_index', where: 'doc_id = ?', whereArgs: [docId], limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> listPageIndices() async {
    final db = await database;
    return db.query('page_index', orderBy: 'created_at DESC');
  }

  Future<void> deletePageIndex(String docId) async {
    final db = await database;
    await db.delete('page_index', where: 'doc_id = ?', whereArgs: [docId]);
  }

  // ===== Trends: Platforms =====
  Future<void> batchUpsertTrendPlatforms(List<({String id, String name, String category})> platforms) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final p in platforms) {
      batch.insert('trend_platforms', {
        'id': p.id,
        'name': p.name,
        'category': p.category,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ===== Trends: Crawl Records =====
  Future<int> insertTrendCrawlRecord(int crawlTime, int newsCount) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('trend_crawl_records', {
      'crawl_time': crawlTime,
      'news_count': newsCount,
      'created_at': now,
    });
    return id;
  }

  Future<Map<String, dynamic>?> getLatestTrendCrawlRecord() async {
    final db = await database;
    final result = await db.query('trend_crawl_records', orderBy: 'created_at DESC', limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int?> getLatestCrawlTimeToday(int todayStart) async {
    final db = await database;
    final result = await db.query(
      'trend_crawl_records',
      where: 'crawl_time >= ?',
      whereArgs: [todayStart],
      orderBy: 'crawl_time DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first['crawl_time'] as int? : null;
  }

  // ===== Trends: Crawl Source Statuses =====
  Future<void> batchInsertTrendCrawlSourceStatuses(List<({int recordId, String platformId, String status})> entries) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final e in entries) {
      batch.insert('trend_crawl_source_statuses', {
        'record_id': e.recordId,
        'platform_id': e.platformId,
        'status': e.status,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  // ===== Trends: News Items =====
  Future<void> batchUpsertTrendNewsItems(List<({
    String title,
    String platformId,
    int rank,
    String url,
    String? mobileUrl,
    String? hotValue,
    String? extra,
    String? cover,
    int? firstCrawlTime,
    int? lastCrawlTime,
    int? crawlCount,
  })> items) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final item in items) {
      // Check if exists by (title, platform_id)
      final existing = await db.query(
        'trend_news_items',
        where: 'title = ? AND platform_id = ?',
        whereArgs: [item.title, item.platformId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        batch.update(
          'trend_news_items',
          {
            'rank': item.rank,
            'url': item.url,
            'mobile_url': item.mobileUrl,
            'hot_value': item.hotValue,
            'extra': item.extra,
            'cover': item.cover,
            'last_crawl_time': now,
            'crawl_count': (row['crawl_count'] as int? ?? 1) + 1,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      } else {
        batch.insert('trend_news_items', {
          'title': item.title,
          'platform_id': item.platformId,
          'rank': item.rank,
          'url': item.url,
          'mobile_url': item.mobileUrl,
          'hot_value': item.hotValue,
          'extra': item.extra,
          'cover': item.cover,
          'first_crawl_time': item.firstCrawlTime ?? now,
          'last_crawl_time': item.lastCrawlTime ?? now,
          'crawl_count': item.crawlCount ?? 1,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, int>> getTrendNewsItemIdsByKeys(List<({String title, String platformId})> keys) async {
    final db = await database;
    final result = <String, int>{};
    for (final key in keys) {
      final rows = await db.query(
        'trend_news_items',
        columns: ['id'],
        where: 'title = ? AND platform_id = ?',
        whereArgs: [key.title, key.platformId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        result['${key.title}|${key.platformId}'] = rows.first['id'] as int;
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getTrendNewsItems({String? platformId, int limit = 100}) async {
    final db = await database;
    var where = '';
    final args = <dynamic>[];
    if (platformId != null) {
      where = 'platform_id = ?';
      args.add(platformId);
    }
    return db.query(
      'trend_news_items',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'last_crawl_time DESC',
      limit: limit,
    );
  }

  // ===== Trends: Rank History =====
  Future<void> batchInsertTrendRankHistory(List<({int newsItemId, int rank, int crawlTime})> entries) async {
    final db = await database;
    final batch = db.batch();
    for (final e in entries) {
      batch.insert('trend_rank_history', {
        'news_item_id': e.newsItemId,
        'rank': e.rank,
        'crawl_time': e.crawlTime,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, List<int>>> getTrendRankHistoryBatch(List<int> newsItemIds) async {
    final db = await database;
    if (newsItemIds.isEmpty) return {};
    final placeholders = newsItemIds.map((_) => '?').join(',');
    final result = await db.rawQuery(
      'SELECT news_item_id, rank FROM trend_rank_history WHERE news_item_id IN ($placeholders) ORDER BY crawl_time ASC',
      newsItemIds,
    );
    final map = <int, List<int>>{};
    for (final row in result) {
      final id = row['news_item_id'] as int;
      final rank = row['rank'] as int;
      map.putIfAbsent(id, () => []).add(rank);
    }
    return map;
  }

  // ===== Trends: Today First Time =====
  Future<Map<String, Map<String, int>>> getTodayNewsFirstTime(int todayStart) async {
    final db = await database;
    final result = await db.query(
      'trend_news_items',
      where: 'first_crawl_time >= ?',
      whereArgs: [todayStart],
    );
    final map = <String, Map<String, int>>{};
    for (final row in result) {
      final pid = row['platform_id'] as String;
      final title = row['title'] as String;
      final firstTime = row['first_crawl_time'] as int? ?? 0;
      map.putIfAbsent(pid, () => {})[title] = firstTime;
    }
    return map;
  }

  Future<void> deleteOldTrendNews(int cutoff) async {
    final db = await database;
    // Delete rank history for old news
    await db.rawDelete(
      'DELETE FROM trend_rank_history WHERE news_item_id IN (SELECT id FROM trend_news_items WHERE last_crawl_time < ?)',
      [cutoff],
    );
    await db.delete('trend_news_items', where: 'last_crawl_time < ?', whereArgs: [cutoff]);
  }

  // ===== AI Filter Tags =====
  Future<int> rawInsertAiFilterTag({
    required String tag,
    String? description,
    required int priority,
    required int version,
  }) async {
    final db = await database;
    return await db.insert('ai_filter_tags', {
      'tag': tag,
      'description': description,
      'priority': priority,
      'version': version,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getActiveAiFilterTags() async {
    final db = await database;
    final maxVersion = await db.rawQuery('SELECT MAX(version) as mv FROM ai_filter_tags');
    if (maxVersion.isEmpty || maxVersion.first['mv'] == null) return [];
    final mv = maxVersion.first['mv'] as int;
    return db.query('ai_filter_tags', where: 'version = ?', whereArgs: [mv], orderBy: 'priority ASC');
  }

  Future<int?> upsertAiFilterTag({
    required String tag,
    required String description,
    required int priority,
    required int version,
    int? existingId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existingId != null) {
      await db.update('ai_filter_tags', {
        'tag': tag,
        'description': description,
        'priority': priority,
        'version': version,
      }, where: 'id = ?', whereArgs: [existingId]);
      return existingId;
    }
    final id = await db.insert('ai_filter_tags', {
      'tag': tag,
      'description': description,
      'priority': priority,
      'version': version,
      'created_at': now,
    });
    return id;
  }

  Future<int?> getLatestAiFilterTagVersion() async {
    final db = await database;
    final result = await db.rawQuery('SELECT MAX(version) as mv FROM ai_filter_tags');
    return result.isNotEmpty ? result.first['mv'] as int? : null;
  }

  // ===== AI Filter Results =====
  Future<void> insertAiFilterResult({
    required int newsItemId,
    int? tagId,
    double relevanceScore = 0.0,
  }) async {
    final db = await database;
    final version = await getLatestAiFilterTagVersion();
    await db.insert('ai_filter_results', {
      'news_item_id': newsItemId,
      'tag_id': tagId,
      'relevance_score': relevanceScore,
      'tag_version': version,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getAiFilterResults({int? tagVersion}) async {
    final db = await database;
    if (tagVersion != null) {
      return db.query('ai_filter_results', where: 'tag_version = ?', whereArgs: [tagVersion], orderBy: 'relevance_score DESC');
    }
    return db.query('ai_filter_results', orderBy: 'relevance_score DESC');
  }
}
