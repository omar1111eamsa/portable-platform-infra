cmake_minimum_required(VERSION 3.10)
project(user_management_service LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -Wall -Wextra -pthread")

# include headers
include_directories(${CMAKE_SOURCE_DIR}/include)
include_directories(${CMAKE_SOURCE_DIR}/third_party/jwt-cpp/include)
include_directories(/usr/local/include)

find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED)

# Ensure JWT key material exists for local builds
find_program(OPENSSL_EXECUTABLE openssl)
if(NOT OPENSSL_EXECUTABLE)
    message(FATAL_ERROR "OpenSSL executable not found; required to generate keys/private.pem and keys/public.pem")
endif()

set(KEYS_DIR ${CMAKE_SOURCE_DIR}/keys)
if(NOT EXISTS ${KEYS_DIR})
    file(MAKE_DIRECTORY ${KEYS_DIR})
endif()

set(PRIVATE_KEY_FILE ${KEYS_DIR}/private.pem)
set(PUBLIC_KEY_FILE ${KEYS_DIR}/public.pem)

if(NOT EXISTS ${PRIVATE_KEY_FILE})
    execute_process(
        COMMAND ${OPENSSL_EXECUTABLE} genrsa -out ${PRIVATE_KEY_FILE} 2048
        RESULT_VARIABLE GENRSA_RESULT
    )
    if(NOT GENRSA_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to generate ${PRIVATE_KEY_FILE}")
    endif()
endif()

if(NOT EXISTS ${PUBLIC_KEY_FILE})
    execute_process(
        COMMAND ${OPENSSL_EXECUTABLE} rsa -in ${PRIVATE_KEY_FILE} -pubout -out ${PUBLIC_KEY_FILE}
        RESULT_VARIABLE PUBOUT_RESULT
    )
    if(NOT PUBOUT_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to generate ${PUBLIC_KEY_FILE}")
    endif()
endif()

# collect all .cpp sources in src/ (adds any new files automatically)
file(GLOB SRC_FILES "${CMAKE_SOURCE_DIR}/src/*.cpp")

# sanity check
if(NOT SRC_FILES)
    message(FATAL_ERROR "No source files found in src/ - please check your directory")
endif()

message(STATUS "Source files: ${SRC_FILES}")

add_executable(user_management_service ${SRC_FILES})

# Link system libs
target_link_libraries(user_management_service
    PRIVATE
    pqxx
    ${OPENSSL_LIBRARIES}
    Threads::Threads
    sodium
    hiredis
    crypt
)

# Installation (optional)
install(TARGETS user_management_service DESTINATION bin)

enable_testing()

add_executable(user_management_tests
    tests/test_main.cpp
    tests/test_auth_manager.cpp
    tests/test_auth_manager_edgecases.cpp
    tests/test_bcrypt_utils.cpp
    tests/test_user_controller.cpp
    tests/test_user_controller_edgecases.cpp
    tests/test_subscription_manager.cpp
    tests/test_logger.cpp
    src/auth_manager.cpp
    src/bcrypt_utils.cpp
    src/logger.cpp
    src/user_controller.cpp
    src/subscription_manager.cpp
    src/db.cpp
)

target_include_directories(user_management_tests
    PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/tests
)

target_compile_definitions(user_management_tests
    PRIVATE
    UNIT_TESTING
    TEST_KEYS_DIR="${CMAKE_SOURCE_DIR}/keys"
)

target_link_libraries(user_management_tests
    PRIVATE
    pqxx
    ${OPENSSL_LIBRARIES}
    Threads::Threads
    sodium
    hiredis
    crypt
)

add_test(NAME unit_tests COMMAND user_management_tests)
