<?php
/**
 * Chunked File Upload Endpoint for SRIHER Digital Signage
 * -------------------------------------------------------
 * This file handles large video uploads by receiving them in small chunks
 * that fit under the nginx client_max_body_size limit (1MB).
 *
 * DEPLOYMENT:
 *   1. Place this file in your Laravel routes or create a new route pointing to it.
 *   2. Or add the route in routes/api.php:
 *
 *      Route::post('/chunkedUpload', [FileController::class, 'chunkedUpload']);
 *
 * HOW IT WORKS:
 *   - Client splits large file into base64 chunks (~500KB each)
 *   - Each chunk is sent as a JSON POST with chunk_index, total_chunks, upload_id
 *   - Server stores chunks in a temp directory
 *   - On the final chunk, server assembles the file and calls the existing
 *     insertFileview logic to store it properly
 */

// ──── CONFIGURATION ─────────────────────────────────────────────────────────
$API_KEY = "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
$CHUNK_DIR = sys_get_temp_dir() . '/sriher_chunks/';

// ──── CORS HEADERS ──────────────────────────────────────────────────────────
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ──── PARSE INPUT ───────────────────────────────────────────────────────────
$input = json_decode(file_get_contents('php://input'), true);

if (!$input || !isset($input['api_key']) || $input['api_key'] !== $API_KEY) {
    echo json_encode(['status' => 'Failed', 'Message' => 'Wrong api key']);
    exit;
}

$action = $input['action'] ?? '';

// ──── ACTION: INIT ──────────────────────────────────────────────────────────
// Client calls this first to get a unique upload_id
if ($action === 'init') {
    $upload_id = uniqid('upload_', true);
    $upload_dir = $CHUNK_DIR . $upload_id . '/';
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0755, true);
    }
    echo json_encode([
        'status' => 'Success',
        'upload_id' => $upload_id,
    ]);
    exit;
}

// ──── ACTION: CHUNK ─────────────────────────────────────────────────────────
// Client sends each chunk here
if ($action === 'chunk') {
    $upload_id   = $input['upload_id'] ?? '';
    $chunk_index = intval($input['chunk_index'] ?? -1);
    $total_chunks = intval($input['total_chunks'] ?? 0);
    $chunk_data  = $input['chunk_data'] ?? '';

    if (empty($upload_id) || $chunk_index < 0 || empty($chunk_data)) {
        echo json_encode(['status' => 'Failed', 'Message' => 'Invalid chunk data']);
        exit;
    }

    $upload_dir = $CHUNK_DIR . $upload_id . '/';
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0755, true);
    }

    // Decode base64 chunk and save to disk
    $decoded = base64_decode($chunk_data);
    if ($decoded === false) {
        echo json_encode(['status' => 'Failed', 'Message' => 'Invalid base64 data']);
        exit;
    }

    $chunk_file = $upload_dir . 'chunk_' . str_pad($chunk_index, 5, '0', STR_PAD_LEFT);
    file_put_contents($chunk_file, $decoded);

    echo json_encode([
        'status' => 'Success',
        'Message' => "Chunk $chunk_index received",
        'chunk_index' => $chunk_index,
    ]);
    exit;
}

// ──── ACTION: COMPLETE ──────────────────────────────────────────────────────
// Client calls this after all chunks are sent; server assembles and processes
if ($action === 'complete') {
    $upload_id    = $input['upload_id'] ?? '';
    $filename     = $input['filename'] ?? 'video.mp4';
    $category_id  = $input['category_id'] ?? '';
    $name         = $input['name'] ?? '';
    $desc         = $input['desc'] ?? '';
    $group5       = $input['group5'] ?? 'Permanent';
    $file_duration = $input['file_duration'] ?? '25';

    // Date fields
    $valid_from_date = $input['valid_from_date'] ?? '';
    $valid_upto_date = $input['valid_upto_date'] ?? '';
    $from_date       = $input['from_date'] ?? '';
    $to_date         = $input['to_date'] ?? '';
    $valid_from      = $input['valid_from'] ?? '';
    $valid_upto      = $input['valid_upto'] ?? '';

    $upload_dir = $CHUNK_DIR . $upload_id . '/';

    if (!is_dir($upload_dir)) {
        echo json_encode(['status' => 'Failed', 'Message' => 'Upload session not found']);
        exit;
    }

    // Assemble chunks into final file
    $chunks = glob($upload_dir . 'chunk_*');
    if (empty($chunks)) {
        echo json_encode(['status' => 'Failed', 'Message' => 'No chunks found']);
        exit;
    }
    sort($chunks); // Ensure correct order

    $final_path = $upload_dir . $filename;
    $fp = fopen($final_path, 'wb');
    foreach ($chunks as $chunk_file) {
        $data = file_get_contents($chunk_file);
        fwrite($fp, $data);
        unlink($chunk_file); // Clean up chunk
    }
    fclose($fp);

    // Now move the assembled file to the uploads directory and insert into DB
    // This replicates the logic in your existing insertFileview endpoint
    $ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
    $timestamp = date('YmdHis');
    $stored_name = "VID-{$timestamp}-{$filename}";

    // Determine the uploads path (adjust to match your Laravel storage)
    $uploads_dir = __DIR__ . '/../public/uploads/';
    if (!is_dir($uploads_dir)) {
        $uploads_dir = __DIR__ . '/../../public/uploads/';
    }
    // Fallback: try the standard Laravel public path
    if (!is_dir($uploads_dir)) {
        $uploads_dir = base_path('public/uploads/');
    }

    // Attempt to move the file
    $dest = $uploads_dir . $stored_name;
    if (!rename($final_path, $dest)) {
        // If rename fails, try copy
        copy($final_path, $dest);
        unlink($final_path);
    }

    // Clean up temp directory
    @rmdir($upload_dir);

    // Determine file type
    $file_type = strtoupper($ext);
    $file_format = '';
    if (in_array($ext, ['mp4', 'mov', 'avi', 'mkv', 'webm'])) {
        $file_format = "video/$ext";
    } else if (in_array($ext, ['jpg', 'jpeg', 'png', 'gif', 'webp'])) {
        $file_format = "image/" . ($ext === 'jpg' ? 'jpeg' : $ext);
    }

    // Insert into database (adjust table/column names to match your schema)
    try {
        // Use Laravel's DB if available
        if (function_exists('app')) {
            $db = app('db');
            $db->table('file_masters')->insert([
                'file_name'       => $stored_name,
                'user_filename'   => $name,
                'description'     => $desc,
                'category_id'     => $category_id,
                'type'            => $group5,
                'file_status'     => 1,
                'file_type'       => $file_type,
                'file_format'     => $file_format,
                'file_duration'   => $file_duration,
                'valid_from_date' => $valid_from_date ?: null,
                'valid_upto_date' => $valid_upto_date ?: null,
                'status'          => 0,
                'created_at'      => now(),
                'updated_at'      => now(),
            ]);
        } else {
            // Direct PDO fallback
            // You'll need to update these credentials
            $pdo = new PDO('mysql:host=localhost;dbname=your_db', 'user', 'pass');
            $stmt = $pdo->prepare("INSERT INTO file_masters 
                (file_name, user_filename, description, category_id, type, file_status, file_type, file_format, file_duration, valid_from_date, valid_upto_date, status) 
                VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, 0)");
            $stmt->execute([
                $stored_name, $name, $desc, $category_id, $group5,
                $file_type, $file_format, $file_duration,
                $valid_from_date ?: null, $valid_upto_date ?: null
            ]);
        }

        echo json_encode([
            'status'  => 'Success',
            'Message' => 'File uploaded successfully',
            'file_name' => $stored_name,
        ]);
    } catch (Exception $e) {
        echo json_encode([
            'status'  => 'Failed',
            'Message' => 'DB insert failed: ' . $e->getMessage(),
        ]);
    }
    exit;
}

echo json_encode(['status' => 'Failed', 'Message' => 'Unknown action']);
