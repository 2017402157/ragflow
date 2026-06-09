-- MaaS 多租户数据隔离迁移脚本 - ragflow
-- 为核心业务表添加 tenant_id 字段
-- 执行前提：ragflow 数据库已初始化
-- 幂等性：使用 IF NOT EXISTS

-- user 表：添加 tenant_id
ALTER TABLE user ADD COLUMN IF NOT EXISTS tenant_id BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_user_tenant_id ON user (tenant_id);

-- knowledgebase 表：添加 tenant_id + dept_id
ALTER TABLE knowledgebase ADD COLUMN IF NOT EXISTS tenant_id BIGINT DEFAULT 0;
ALTER TABLE knowledgebase ADD COLUMN IF NOT EXISTS dept_id BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_knowledgebase_tenant_id ON knowledgebase (tenant_id);
CREATE INDEX IF NOT EXISTS idx_knowledgebase_dept_id ON knowledgebase (dept_id);

-- document 表：添加 tenant_id
ALTER TABLE document ADD COLUMN IF NOT EXISTS tenant_id BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_document_tenant_id ON document (tenant_id);

-- dialog 表：添加 tenant_id
ALTER TABLE dialog ADD COLUMN IF NOT EXISTS tenant_id BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_dialog_tenant_id ON dialog (tenant_id);

-- conversation 表：添加 tenant_id
ALTER TABLE conversation ADD COLUMN IF NOT EXISTS tenant_id BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_conversation_tenant_id ON conversation (tenant_id);

-- 验证迁移
SELECT table_name, column_name FROM information_schema.columns
WHERE column_name IN ('tenant_id', 'dept_id')
ORDER BY table_name, column_name;