<?php
/**
 * Laravel Route Registration for Chunked Upload
 * ──────────────────────────────────────────────
 * Add this route to your routes/api.php or routes/web.php file
 * on the display.sriher.com server.
 */

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::post('/chunkedUpload', function (Request $request) {
    $API_KEY = "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
    $CHUNK_DIR = storage_path('app/chunks/');

    $input = $request->all();

    // Validate API key
    if (($input['api_key'] ?? '') !== $API_KEY) {
        return response()->json(['status' => 'Failed', 'Message' => 'Wrong api key']);
    }

    $action = $input['action'] ?? '';

    // ──── INIT: Create upload session ────────────────────────────────────────
    if ($action === 'init') {
        $upload_id = uniqid('upload_', true);
        $upload_dir = $CHUNK_DIR . $upload_id . '/';
        if (!is_dir($upload_dir)) {
            mkdir($upload_dir, 0755, true);
        }
        return response()->json([
            'status'    => 'Success',
            'upload_id' => $upload_id,
        ]);
    }

    // ──── CHUNK: Receive a single chunk ──────────────────────────────────────
    if ($action === 'chunk') {
        $upload_id   = $input['upload_id'] ?? '';
        $chunk_index = intval($input['chunk_index'] ?? -1);
        $chunk_data  = $input['chunk_data'] ?? '';

        if (empty($upload_id) || $chunk_index < 0 || empty($chunk_data)) {
            return response()->json(['status' => 'Failed', 'Message' => 'Invalid chunk data']);
        }

        $upload_dir = $CHUNK_DIR . $upload_id . '/';
        if (!is_dir($upload_dir)) {
            mkdir($upload_dir, 0755, true);
        }

        $decoded = base64_decode($chunk_data);
        if ($decoded === false) {
            return response()->json(['status' => 'Failed', 'Message' => 'Invalid base64']);
        }

        $chunk_file = $upload_dir . 'chunk_' . str_pad($chunk_index, 5, '0', STR_PAD_LEFT);
        file_put_contents($chunk_file, $decoded);

        return response()->json([
            'status'      => 'Success',
            'Message'     => "Chunk $chunk_index received",
            'chunk_index' => $chunk_index,
        ]);
    }

    // ──── COMPLETE: Assemble chunks and insert into DB ──────────────────────
    if ($action === 'complete') {
        $upload_id    = $input['upload_id'] ?? '';
        $filename     = $input['filename'] ?? 'video.mp4';
        $category_id  = $input['category_id'] ?? '';
        $name         = $input['name'] ?? '';
        $desc         = $input['desc'] ?? '';
        $group5       = $input['group5'] ?? 'Permanent';
        $file_duration = $input['file_duration'] ?? '25';
        $valid_from_date = $input['valid_from_date'] ?? null;
        $valid_upto_date = $input['valid_upto_date'] ?? null;

        $upload_dir = $CHUNK_DIR . $upload_id . '/';
        if (!is_dir($upload_dir)) {
            return response()->json(['status' => 'Failed', 'Message' => 'Upload session not found']);
        }

        // Assemble all chunks into one file
        $chunks = glob($upload_dir . 'chunk_*');
        if (empty($chunks)) {
            return response()->json(['status' => 'Failed', 'Message' => 'No chunks found']);
        }
        sort($chunks);

        $ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
        $timestamp = date('YmdHis');
        $stored_name = "VID-{$timestamp}-{$filename}";

        $dest = public_path('uploads/' . $stored_name);

        // Ensure uploads directory exists
        if (!is_dir(public_path('uploads'))) {
            mkdir(public_path('uploads'), 0755, true);
        }

        // Write assembled file directly to uploads
        $fp = fopen($dest, 'wb');
        foreach ($chunks as $chunk_file) {
            fwrite($fp, file_get_contents($chunk_file));
            unlink($chunk_file);
        }
        fclose($fp);

        // Remove temp directory
        @rmdir($upload_dir);

        // Determine file type/format
        $file_type = strtoupper($ext);
        $file_format = '';
        if (in_array($ext, ['mp4', 'mov', 'avi', 'mkv', 'webm'])) {
            $file_format = "video/$ext";
        } elseif (in_array($ext, ['jpg', 'jpeg', 'png', 'gif', 'webp'])) {
            $file_format = "image/" . ($ext === 'jpg' ? 'jpeg' : $ext);
        }

        // Insert into database
        try {
            DB::table('file_masters')->insert([
                'file_name'       => $stored_name,
                'user_filename'   => $name,
                'description'     => $desc,
                'category_id'     => $category_id,
                'type'            => $group5,
                'file_status'     => 1,
                'file_type'       => $file_type,
                'file_format'     => $file_format,
                'file_duration'   => $file_duration,
                'valid_from_date' => $valid_from_date,
                'valid_upto_date' => $valid_upto_date,
                'status'          => 0,
                'created_at'      => now(),
                'updated_at'      => now(),
            ]);

            return response()->json([
                'status'    => 'Success',
                'Message'   => 'File uploaded successfully',
                'file_name' => $stored_name,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'status'  => 'Failed',
                'Message' => 'DB insert failed: ' . $e->getMessage(),
            ]);
        }
    }

    return response()->json(['status' => 'Failed', 'Message' => 'Unknown action']);
});
