#include <jni.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <android/asset_manager_jni.h>
#include <android/log.h>

#include <opencv2/core/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/highgui/highgui.hpp>

#include <platform.h>

#include "ppocrv5.h"
#include "ppocrv5_dict.h"

#define TAG "MyOCR"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static PPOCRv5* g_ocr = nullptr;
static bool g_loaded = false;
static ncnn::Mutex g_ocrMutex;

// Helper: escape JSON string
static std::string jsonEscape(const std::string& s) {
    std::string o;
    for (size_t i = 0; i < s.size(); i++) {
        char c = s[i];
        if (c == '"') o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else if (c == '\r') o += "\\r";
        else if (c == '\t') o += "\\t";
        else o += c;
    }
    return o;
}

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_agent_my_1agent_1app_OcrEngine_nLoadModel(
    JNIEnv* env, jobject thiz, jobject assetManager, jboolean useGpu) {

    ncnn::MutexLockGuard guard(g_ocrMutex);

    if (g_loaded) {
        return JNI_TRUE;
    }

    AAssetManager* mgr = AAssetManager_fromJava(env, assetManager);
    LOGD("Loading OCR models...");

    if (g_ocr) {
        delete g_ocr;
        g_ocr = nullptr;
    }

    g_ocr = new PPOCRv5;

    const char* det_param = "PP_OCRv5_mobile_det.ncnn.param";
    const char* det_model = "PP_OCRv5_mobile_det.ncnn.bin";
    const char* rec_param = "PP_OCRv5_mobile_rec.ncnn.param";
    const char* rec_model = "PP_OCRv5_mobile_rec.ncnn.bin";

    bool use_gpu = (bool)useGpu;
    bool use_fp16 = true;

    int ret = g_ocr->load(mgr, det_param, det_model, rec_param, rec_model, use_fp16, use_gpu);
    if (ret != 0) {
        LOGE("Failed to load OCR models");
        delete g_ocr;
        g_ocr = nullptr;
        return JNI_FALSE;
    }

    g_ocr->set_target_size(640);
    g_loaded = true;
    LOGD("OCR models loaded successfully");
    return JNI_TRUE;
}

JNIEXPORT jstring JNICALL
Java_com_agent_my_1agent_1app_OcrEngine_nRecognize(
    JNIEnv* env, jobject thiz, jstring imagePath) {

    LOGD("nRecognize called");

    // Read the check before acquiring lock to avoid blocking on uninitialized engine
    if (!g_ocr || !g_loaded) {
        LOGE("OCR not initialized");
        return env->NewStringUTF("");
    }

    const char* path = env->GetStringUTFChars(imagePath, nullptr);
    if (!path) return env->NewStringUTF("");

    LOGD("Loading image: %s", path);
    cv::Mat rgb = cv::imread(path, cv::IMREAD_COLOR);
    env->ReleaseStringUTFChars(imagePath, path);

    if (rgb.empty()) {
        LOGE("Failed to load image");
        return env->NewStringUTF("");
    }

    LOGD("Image loaded: %dx%d", rgb.cols, rgb.rows);

    std::vector<Object> objects;
    {
        ncnn::MutexLockGuard guard(g_ocrMutex);
        LOGD("Running detect_and_recognize...");
        g_ocr->detect_and_recognize(rgb, objects);
        LOGD("detect_and_recognize done, found %d objects", objects.size());
    }

    // Build JSON result with position data
    std::ostringstream json;
    json << "{\"texts\":[";
    for (size_t i = 0; i < objects.size(); i++) {
        const Object& obj = objects[i];

        // Build text string
        std::string text;
        for (size_t j = 0; j < obj.text.size(); j++) {
            const Character& ch = obj.text[j];
            if (ch.id >= 0 && ch.id < character_dict_size) {
                text += character_dict[ch.id];
            }
        }

        if (i > 0) json << ",";

        // Get rotated rectangle points
        cv::Point2f pts[4];
        obj.rrect.points(pts);

        json << "{\"text\":\"" << jsonEscape(text) << "\""
            << ",\"confidence\":" << std::fixed << std::setprecision(2) << obj.prob
            << ",\"text_region\":[";

        // Add 4 corner points
        for (int p = 0; p < 4; p++) {
            if (p > 0) json << ",";
            json << "[" << pts[p].x << "," << pts[p].y << "]";
        }
        json << "]";

        // Add center, angle, width, height
        json << ",\"center\":[" << obj.rrect.center.x << "," << obj.rrect.center.y << "]"
            << ",\"angle\":" << obj.rrect.angle
            << ",\"width\":" << obj.rrect.size.width
            << ",\"height\":" << obj.rrect.size.height
            << ",\"orientation\":" << obj.orientation;

        json << "}";
    }
    json << "]}";

    return env->NewStringUTF(json.str().c_str());
}

JNIEXPORT void JNICALL
Java_com_agent_my_1agent_1app_OcrEngine_nDispose(
    JNIEnv* env, jobject thiz) {

    ncnn::MutexLockGuard guard(g_ocrMutex);
    LOGD("Disposing OCR engine");
    if (g_ocr) {
        delete g_ocr;
        g_ocr = nullptr;
    }
    g_loaded = false;
}

} // extern "C"
