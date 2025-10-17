#!/bin/bash

# Docker镜像构建脚本
# 用法: ./build-docker.sh [app-name] [environment]
# 示例: ./build-docker.sh first-app develop

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 应用列表
APPS=("first-app" "second-app" "web-app")
ENVIRONMENTS=("develop" "staging" "prod")

# 显示帮助信息
show_help() {
    echo "🐳 Docker镜像构建脚本"
    echo ""
    echo "用法: $0 [app-name] [environment] [options]"
    echo ""
    echo "参数:"
    echo "  app-name     应用名称: ${APPS[*]}"
    echo "  environment 环境名称: ${ENVIRONMENTS[*]}"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示帮助信息"
    echo "  -l, --list          列出所有可用的应用和环境"
    echo "  -a, --all           构建所有应用的所有环境"
    echo "  -p, --push          构建完成后推送到镜像仓库"
    echo "  -t, --tag TAG       指定镜像标签 (默认: app-env-commit)"
    echo "  --no-cache          构建时不使用缓存"
    echo ""
    echo "示例:"
    echo "  $0 first-app develop              # 构建first-app的develop环境"
    echo "  $0 second-app prod --push         # 构建second-app的prod环境并推送"
    echo "  $0 --all                          # 构建所有应用的所有环境"
    echo ""
}

# 列出应用和环境
list_apps_envs() {
    echo "📋 可用的应用和环境:"
    echo ""
    for app in "${APPS[@]}"; do
        echo "🔧 $app:"
        for env in "${ENVIRONMENTS[@]}"; do
            config_file=$(get_config_info "$app" "$env")
            dockerfile="deploy/docker/${app}/Dockerfile"

            if [[ -f "$config_file" ]] && [[ -f "$dockerfile" ]]; then
                echo "  ✅ $env (配置文件: $config_file)"
            else
                echo "  ❌ $env (缺少配置文件或Dockerfile)"
                if [[ -z "$config_file" ]]; then
                    echo "    原因: 无法确定配置文件路径"
                elif [[ ! -f "$config_file" ]]; then
                    echo "    原因: 配置文件不存在 ($config_file)"
                elif [[ ! -f "$dockerfile" ]]; then
                    echo "    原因: Dockerfile不存在 ($dockerfile)"
                fi
            fi
        done
        echo ""
    done
}

# 获取应用的配置文件路径和格式
get_config_info() {
    local app=$1
    local env=$2

    case "$app" in
        "first-app")
            echo "backend/app/first_app/config/config-${env}.yaml"
            ;;
        "second-app")
            echo "backend/app/second_app/config/config-${env}.yaml"
            ;;
        "web-app")
            echo "frontend/first_app/config/config-${env}.json"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 检查应用和环境是否存在
check_app_env() {
    local app=$1
    local env=$2

    # 检查应用是否在列表中
    if [[ ! " ${APPS[@]} " =~ " ${app} " ]]; then
        echo -e "${RED}❌ 错误: 未知的应用 '$app'${NC}"
        echo -e "${YELLOW}可用应用: ${APPS[*]}${NC}"
        exit 1
    fi

    # 检查环境是否在列表中
    if [[ ! " ${ENVIRONMENTS[@]} " =~ " ${env} " ]]; then
        echo -e "${RED}❌ 错误: 未知的环境 '$env'${NC}"
        echo -e "${YELLOW}可用环境: ${ENVIRONMENTS[*]}${NC}"
        exit 1
    fi

    # 智能检测配置文件路径
    local config_file
    config_file=$(get_config_info "$app" "$env")

    if [[ -z "$config_file" ]]; then
        echo -e "${RED}❌ 错误: 无法确定应用 '$app' 的配置文件路径${NC}"
        exit 1
    fi

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}❌ 错误: 配置文件不存在: $config_file${NC}"
        echo -e "${YELLOW}应用 '$app' 的环境 '$env' 配置文件应为: $config_file${NC}"
        exit 1
    fi

    # 检查Dockerfile是否存在
    local dockerfile="deploy/docker/${app}/Dockerfile"
    if [[ ! -f "$dockerfile" ]]; then
        echo -e "${RED}❌ 错误: Dockerfile不存在: $dockerfile${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ 配置验证通过: $config_file${NC}"
}

# 构建单个镜像
build_image() {
    local app=$1
    local env=$2
    local extra_args=()

    # 构建参数
    if [[ "$NO_CACHE" == "true" ]]; then
        extra_args+=(--no-cache)
    fi

    # 生成镜像标签
    local commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local image_tag="${app}-${env}-${commit_hash}"

    if [[ -n "$CUSTOM_TAG" ]]; then
        image_tag="$CUSTOM_TAG"
    fi

    local image_name="${app}:${image_tag}"
    local latest_name="${app}:latest-${env}"

    # 获取配置文件路径用于显示
    local config_file
    config_file=$(get_config_info "$app" "$env")

    echo -e "${BLUE}🔨 开始构建镜像: $app ($env)${NC}"
    echo -e "${BLUE}📁 Dockerfile: deploy/docker/${app}/Dockerfile${NC}"
    echo -e "${BLUE}⚙️  配置文件: $config_file${NC}"
    echo -e "${BLUE}🏷️  镜像标签: $image_name${NC}"
    echo ""

    # 构建镜像
    docker build \
        --build-arg CONFIG_ENV="$env" \
        -f "deploy/docker/${app}/Dockerfile" \
        -t "$image_name" \
        -t "$latest_name" \
        "${extra_args[@]}" \
        .

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ 构建成功: $image_name${NC}"

        # 推送镜像
        if [[ "$PUSH_IMAGE" == "true" ]]; then
            echo -e "${BLUE}📤 推送镜像到仓库...${NC}"
            docker push "$image_name"
            docker push "$latest_name"
            echo -e "${GREEN}✅ 推送成功${NC}"
        fi

        # 显示镜像信息
        echo ""
        echo -e "${GREEN}📊 镜像信息:${NC}"
        docker images | grep "$app" | head -2

        return 0
    else
        echo -e "${RED}❌ 构建失败: $app ($env)${NC}"
        return 1
    fi
}

# 构建所有应用的所有环境
build_all() {
    echo -e "${BLUE}🚀 构建所有应用的所有环境...${NC}"
    echo ""

    local total=0
    local success=0
    local failed=0
    local skipped=0

    for app in "${APPS[@]}"; do
        for env in "${ENVIRONMENTS[@]}"; do
            ((total++))

            config_file=$(get_config_info "$app" "$env")
            dockerfile="deploy/docker/${app}/Dockerfile"

            if [[ -f "$config_file" ]] && [[ -f "$dockerfile" ]]; then
                echo -e "${YELLOW}[$total/${#APPS[@]} * ${#ENVIRONMENTS[@]}] 构建: $app ($env)${NC}"

                if build_image "$app" "$env"; then
                    ((success++))
                else
                    ((failed++))
                fi
                echo ""
            else
                echo -e "${YELLOW}⚠️  跳过: $app ($env) - 缺少配置文件或Dockerfile${NC}"
                if [[ -z "$config_file" ]]; then
                    echo "    原因: 无法确定配置文件路径"
                elif [[ ! -f "$config_file" ]]; then
                    echo "    原因: 配置文件不存在 ($config_file)"
                elif [[ ! -f "$dockerfile" ]]; then
                    echo "    原因: Dockerfile不存在 ($dockerfile)"
                fi
                ((skipped++))
                echo ""
            fi
        done
    done

    # 构建总结
    echo -e "${GREEN}📈 构建总结:${NC}"
    echo -e "${GREEN}  ✅ 成功: $success${NC}"
    echo -e "${RED}  ❌ 失败: $failed${NC}"
    echo -e "${YELLOW}  ⚠️  跳过: $skipped${NC}"

    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
}

# 主函数
main() {
    local app=""
    local env=""
    local build_all_flag=false

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_apps_envs
                exit 0
                ;;
            -a|--all)
                build_all_flag=true
                shift
                ;;
            -p|--push)
                PUSH_IMAGE=true
                shift
                ;;
            -t|--tag)
                CUSTOM_TAG="$2"
                shift 2
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            -*)
                echo -e "${RED}❌ 错误: 未知选项 $1${NC}"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$app" ]]; then
                    app="$1"
                elif [[ -z "$env" ]]; then
                    env="$1"
                else
                    echo -e "${RED}❌ 错误: 过多的参数 '$1'${NC}"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # 执行构建
    if [[ "$build_all_flag" == "true" ]]; then
        build_all
    elif [[ -n "$app" ]] && [[ -n "$env" ]]; then
        check_app_env "$app" "$env"
        build_image "$app" "$env"
    else
        echo -e "${RED}❌ 错误: 请指定应用和环境，或使用 --all 构建所有${NC}"
        echo ""
        show_help
        exit 1
    fi
}

# 检查Docker是否可用
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ 错误: Docker未安装或不在PATH中${NC}"
    exit 1
fi

# 检查Docker daemon是否运行
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ 错误: Docker daemon未运行${NC}"
    exit 1
fi

# 执行主函数
main "$@"