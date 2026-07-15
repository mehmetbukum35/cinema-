-- Migration 015: "Birlikte Seç" (couch_sessions) tablosunun Türkçe/UTF-8 karakter desteğini düzeltmek için charset/collation güncellemesi.
ALTER TABLE couch_sessions CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
