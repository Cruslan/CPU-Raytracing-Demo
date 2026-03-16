#include <QApplication>
#include <QMainWindow>
#include <QWidget>
#include <QImage>
#include <QPainter>
#include <QElapsedTimer>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QCursor>
#include <QDebug>
#include <cmath>
#include <vector>
#include <set>
#include "raytracer.h"

// Basic Vector utilities
Vector3 normalize(Vector3 v) {
    float len = std::sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if (len == 0.0f) return {0.0f, 0.0f, 0.0f, 0.0f};
    return {v.x/len, v.y/len, v.z/len, 0.0f};
}

Vector3 cross(Vector3 a, Vector3 b) {
    return {
        a.y*b.z - a.z*b.y,
        a.z*b.x - a.x*b.z,
        a.x*b.y - a.y*b.x,
        0.0f
    };
}

class RaytracerWidget : public QWidget {
    Q_OBJECT
public:
    RaytracerWidget(QWidget *parent = nullptr) : QWidget(parent) {
        setFixedSize(800, 600);
        image = QImage(800, 600, QImage::Format_ARGB32);
        
        m_camPos = {0.0f, 0.0f, 0.0f, 0.0f};
        m_yaw = -90.0f; // Look towards -Z
        m_pitch = 0.0f;
        setupScene();
        
        m_globalTimer.start();
        m_lastTime = m_globalTimer.elapsed();
    }

protected:
    void keyPressEvent(QKeyEvent *event) override {
        m_keys.insert(event->key());
    }

    void keyReleaseEvent(QKeyEvent *event) override {
        m_keys.erase(event->key());
    }

    bool m_ignoreMouse = false;
    bool m_isDragging = false;
    QPoint m_lastMousePos;

    void mousePressEvent(QMouseEvent *event) override {
        if (event->button() == Qt::LeftButton || event->button() == Qt::RightButton) {
            m_isDragging = true;
            m_lastMousePos = event->pos();
            setCursor(Qt::BlankCursor);
        }
    }

    void mouseReleaseEvent(QMouseEvent *event) override {
        if (event->button() == Qt::LeftButton || event->button() == Qt::RightButton) {
            m_isDragging = false;
            unsetCursor();
        }
    }

    void mouseMoveEvent(QMouseEvent *event) override {
        if (!m_isDragging) return;

        if (m_ignoreMouse) {
            m_ignoreMouse = false;
            return;
        }

        QPoint delta = event->pos() - m_lastMousePos;
        if (delta.isNull()) return;

        m_yaw += delta.x() * 0.2f;
        m_pitch -= delta.y() * 0.2f;
        if (m_pitch > 89.0f) m_pitch = 89.0f;
        if (m_pitch < -89.0f) m_pitch = -89.0f;

        m_ignoreMouse = true;
        QCursor::setPos(mapToGlobal(m_lastMousePos));
    }

    void paintEvent(QPaintEvent *event) override {
        Q_UNUSED(event);

        qint64 currentTime = m_globalTimer.elapsed();
        float dt = (currentTime - m_lastTime) / 1000.0f;
        m_lastTime = currentTime;

        // Cap dt to prevent huge jumps if window is dragged/frozen
        if (dt > 0.1f) dt = 0.1f;

        updateCamera(dt);
        render_frame((uint32_t*)image.bits(), image.width(), image.height(), &scene);

        QPainter painter(this);
        painter.drawImage(0, 0, image);

        // Update title with smooth FPS
        m_frameCount++;
        m_fpsTimeAccumulator += dt;
        if (m_fpsTimeAccumulator >= 0.5f) {
            int fps = static_cast<int>(m_frameCount / m_fpsTimeAccumulator);
            window()->setWindowTitle(QString("Freecam Raytracer (NASM) - %1 FPS").arg(fps));
            m_frameCount = 0;
            m_fpsTimeAccumulator = 0.0f;
        }

        // Immediately request next frame, allowing Qt to vsync or run unbound properly
        update();
    }

private:
    QImage image;
    SceneData scene;
    Vector3 m_camPos;
    float m_yaw, m_pitch;
    std::set<int> m_keys;
    QElapsedTimer m_globalTimer;
    qint64 m_lastTime;
    
    int m_frameCount = 0;
    float m_fpsTimeAccumulator = 0.0f;

    void updateCamera(float dt) {
        float radYaw = m_yaw * M_PI / 180.0f;
        float radPitch = m_pitch * M_PI / 180.0f;

        Vector3 forward;
        forward.x = std::cos(radYaw) * std::cos(radPitch);
        forward.y = std::sin(radPitch);
        forward.z = std::sin(radYaw) * std::cos(radPitch);
        scene.camera_forward = normalize(forward);

        Vector3 worldUp = {0.0f, 1.0f, 0.0f, 0.0f};
        scene.camera_right = normalize(cross(scene.camera_forward, worldUp));
        scene.camera_up = cross(scene.camera_right, scene.camera_forward);

        float speed = 5.0f * dt; // Move 5 units per second
        if (m_keys.count(Qt::Key_W)) {
            m_camPos.x += scene.camera_forward.x * speed;
            m_camPos.y += scene.camera_forward.y * speed;
            m_camPos.z += scene.camera_forward.z * speed;
        }
        if (m_keys.count(Qt::Key_S)) {
            m_camPos.x -= scene.camera_forward.x * speed;
            m_camPos.y -= scene.camera_forward.y * speed;
            m_camPos.z -= scene.camera_forward.z * speed;
        }
        if (m_keys.count(Qt::Key_A)) {
            m_camPos.x -= scene.camera_right.x * speed;
            m_camPos.y -= scene.camera_right.y * speed;
            m_camPos.z -= scene.camera_right.z * speed;
        }
        if (m_keys.count(Qt::Key_D)) {
            m_camPos.x += scene.camera_right.x * speed;
            m_camPos.y += scene.camera_right.y * speed;
            m_camPos.z += scene.camera_right.z * speed;
        }
        scene.camera_pos = m_camPos;
    }

    void setupScene() {
        scene.num_spheres = 1;
        // Place the sphere slightly above the ground
        scene.spheres[0].center = {0.0f, 0.5f, -5.0f, 0.0f};
        scene.spheres[0].radius = 1.0f;
        scene.spheres[0].color = {1.0f, 0.0f, 0.0f, 0.0f};

        scene.plane_normal = {0.0f, 1.0f, 0.0f, 0.0f};
        scene.plane_distance = 1.0f; // y = -1
        scene.has_plane = 1;
        scene.light_pos = {2.0f, 2.0f, 0.0f, 0.0f};
    }
};

class RaytracerWindow : public QMainWindow {
    Q_OBJECT
public:
    RaytracerWindow(QWidget *parent = nullptr) : QMainWindow(parent) {
        RaytracerWidget *widget = new RaytracerWidget(this);
        setCentralWidget(widget);
        setFixedSize(800, 600);
        
        // Ensure the central widget gets focus for key events
        widget->setFocusPolicy(Qt::StrongFocus);
        widget->setFocus();
    }
};

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    RaytracerWindow window;
    window.show();
    return app.exec();
}

#include "main.moc"
