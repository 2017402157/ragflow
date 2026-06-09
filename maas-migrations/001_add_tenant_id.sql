-- MaaS 租户映射迁移脚本 - ragflow
--
-- 重要发现：ragflow 的 tenant_id == user_id（一一对应），不是真正的多租户。
-- ragflow 的 Tenant 是"用户对模型的配置空间"（LLM/Embedding/Rerank 模型选择），
-- 不是组织级别的租户隔离。
--
-- 因此，MaaS 的租户隔离在 ragflow 层面的策略是：
-- 1. 创建 maas_tenant_mapping 表：映射 yudao-cloud tenant_id → ragflow user_id
-- 2. 每个 yudao-cloud 用户对应一个 ragflow user（通过 SSO 同步创建）
-- 3. 知识库/对话的数据隔离通过 ragflow 现有的 user_id 机制实现
-- 4. 部门级共享通过扩展 TenantPermission 添加 DEPT 级别实现
--
-- 此脚本创建映射表和部门权限支持字段

-- MaaS 租户映射表
CREATE TABLE IF NOT EXISTS maas_tenant_mapping (
    id VARCHAR(32) PRIMARY KEY,
    yudao_tenant_id BIGINT NOT NULL COMMENT 'yudao-cloud 租户 ID',
    yudao_user_id BIGINT NOT NULL COMMENT 'yudao-cloud 用户 ID',
    ragflow_user_id VARCHAR(32) NOT NULL COMMENT 'ragflow 用户 ID',
    dept_id BIGINT DEFAULT 0 COMMENT 'yudao-cloud 部门 ID',
    created_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_yudao_tenant_id (yudao_tenant_id),
    INDEX idx_yudao_user_id (yudao_user_id),
    INDEX idx_ragflow_user_id (ragflow_user_id),
    INDEX idx_dept_id (dept_id),
    UNIQUE INDEX uk_yudao_user (yudao_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MaaS 租户映射：yudao-cloud 用户 ↔ ragflow 用户';

-- 为 knowledgebase 表添加 dept_id 字段（用于部门级共享）
ALTER TABLE knowledgebase ADD COLUMN IF NOT EXISTS dept_id BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_knowledgebase_dept_id ON knowledgebase (dept_id);

-- 为 dialog 表添加 dept_id 字段
ALTER TABLE dialog ADD COLUMN IF NOT EXISTS dept_id BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_dialog_dept_id ON dialog (dept_id);

-- 验证
SELECT table_name, column_name FROM information_schema.columns
WHERE column_name IN ('dept_id')
AND table_name IN ('knowledgebase', 'dialog')
ORDER BY table_name;