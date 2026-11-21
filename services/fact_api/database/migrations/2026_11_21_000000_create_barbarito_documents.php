<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('barbarito_documents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('branch_id');
            $table->string('origin', 10);
            $table->string('source_reference', 40);
            $table->unsignedBigInteger('native_id')->nullable();
            $table->string('native_type', 20)->nullable();
            $table->string('number', 80);
            $table->string('payload_hash', 64);
            $table->json('payload');
            $table->string('state', 30)->default('DEMO_GENERADO');
            $table->timestamps();
        });
        Schema::create('barbarito_files', function (Blueprint $table) {
            $table->id();
            $table->uuid('document_id');
            $table->string('format', 10);
            $table->string('path');
            $table->string('sha256', 64);
            $table->unsignedInteger('bytes');
            $table->unique(['document_id', 'format']);
        });
        Schema::table('clients', function (Blueprint $table) {
            $table->boolean('barbarito_customer')->default(false);
            $table->boolean('barbarito_supplier')->default(false);
        });
    }
    public function down(): void {
        Schema::dropIfExists('barbarito_files');
        Schema::dropIfExists('barbarito_documents');
        Schema::table('clients', fn (Blueprint $t) => $t->dropColumn(['barbarito_customer','barbarito_supplier']));
    }
};
