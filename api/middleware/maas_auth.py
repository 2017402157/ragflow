"""
MaaS 认证中间件 - ragflow

在 ragflow API 前置，解析 yudao-cloud gateway 签发的 JWT，
将 MaaS 的 tenant_id/user_id 映射为 ragflow 的 user_id（tenant_id）。

ragflow 的 tenant_id == user_id（一一对应），因此需要通过 maas_tenant_mapping 表
查找 yudao-cloud 用户对应的 ragflow 用户。

如果没有 JWT（直接访问 ragflow），则回退到 ragflow 原有的 session 认证。
"""

import logging
import os
import time
from functools import wraps

import jwt
from quart import request, session

logger = logging.getLogger(__name__)

# JWT 配置（从环境变量读取，与 yudao-cloud gateway 的 maas.jwt.secret 一致）
MAAS_JWT_SECRET = os.getenv("MAAS_JWT_SECRET", "")
MAAS_JWT_HEADER = "X-Maas-JWT"


def get_maas_jwt_secret():
    """获取 JWT 密钥，确保长度足够"""
    global MAAS_JWT_SECRET
    if not MAAS_JWT_SECRET:
        MAAS_JWT_SECRET = os.getenv("MAAS_JWT_SECRET", "")
    return MAAS_JWT_SECRET


def verify_maas_jwt(token_str: str) -> dict | None:
    """
    验证 MaaS JWT 签名，返回 claims 字典。
    验证失败返回 None。
    """
    secret = get_maas_jwt_secret()
    if not secret or len(secret) < 32:
        logger.warning("MAAS_JWT_SECRET 未配置或过短，无法验证 JWT")
        return None

    try:
        payload = jwt.decode(
            token_str,
            secret.encode("utf-8"),
            algorithms=["HS256"],
            options={"require": ["exp", "iat"]},
        )
        return payload
    except jwt.ExpiredSignatureError:
        logger.info("MaaS JWT 已过期")
        return None
    except jwt.InvalidTokenError as e:
        logger.warning(f"MaaS JWT 验证失败: {e}")
        return None


def get_ragflow_user_id_from_claims(claims: dict) -> str | None:
    """
    从 JWT claims 中获取 ragflow user_id。

    策略：
    1. 查找 maas_tenant_mapping 表，获取 yudao_user_id 对应的 ragflow_user_id
    2. 如果映射不存在，返回 None（需要先通过用户同步创建 ragflow 用户）

    Args:
        claims: JWT claims 字典，包含 user_id, tenant_id 等

    Returns:
        ragflow user_id（对应 ragflow 的 tenant_id），或 None
    """
    yudao_user_id = claims.get("user_id")
    if not yudao_user_id:
        return None

    try:
        from api.db.services.user_service import UserService
        # 尝试通过 yudao_user_id 查找映射
        # 在 MVP 阶段，假设 ragflow 用户名格式为 "maas_{yudao_user_id}"
        ragflow_username = f"maas_{yudao_user_id}"
        user = UserService.query(username=ragflow_username)
        if user:
            return str(user.id)
    except Exception as e:
        logger.error(f"查找 ragflow 用户映射失败: {e}")

    return None


def maas_auth_required(f):
    """
    MaaS 认证装饰器。
    检查 X-Maas-JWT header，验证 JWT，设置 session 中的用户信息。
    如果没有 JWT，回退到 ragflow 原有认证。
    """

    @wraps(f)
    async def decorated_function(*args, **kwargs):
        jwt_str = request.headers.get(MAAS_JWT_HEADER, "")
        if not jwt_str:
            # 无 JWT，回退到 ragflow 原有认证
            return await f(*args, **kwargs)

        claims = verify_maas_jwt(jwt_str)
        if not claims:
            from quart import jsonify
            return jsonify({"code": 401, "message": "Invalid MaaS JWT"}), 401

        # 获取 ragflow user_id
        ragflow_user_id = get_ragflow_user_id_from_claims(claims)
        if not ragflow_user_id:
            from quart import jsonify
            return jsonify({"code": 403, "message": "User not synced to ragflow"}), 403

        # 设置 session（模拟 ragflow 登录状态）
        session["user"] = ragflow_user_id

        # 在 request context 中存储 MaaS 额外信息
        request.maas_claims = claims
        request.maas_tenant_id = claims.get("tenant_id", 0)
        request.maas_dept_id = claims.get("dept_id", 0)
        request.maas_data_scope = claims.get("data_scope", "")

        return await f(*args, **kwargs)

    return decorated_function
