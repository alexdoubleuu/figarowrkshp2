<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class HealthTest extends TestCase
{
    public function test_tests_run_against_the_dedicated_test_database(): void
    {
        $this->assertSame('figaro_test', DB::connection()->getDatabaseName());
    }

    public function test_health_endpoint_returns_ok(): void
    {
        $this->getJson('/api/health')
            ->assertOk()
            ->assertJson(['status' => 'ok'])
            ->assertJsonStructure(['status', 'db', 'redis']);
    }

    public function test_health_endpoint_reports_database_and_redis_connections(): void
    {
        $this->getJson('/api/health')
            ->assertOk()
            ->assertJsonPath('db', true)
            ->assertJsonPath('redis', true);
    }
}
