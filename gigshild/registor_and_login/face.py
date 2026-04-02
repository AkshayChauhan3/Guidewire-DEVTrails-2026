import face_recognition

def compare_faces(img1_path, img2_path):
    try:
        img1 = face_recognition.load_image_file(img1_path)
        img2 = face_recognition.load_image_file(img2_path)

        enc1 = face_recognition.face_encodings(img1)
        enc2 = face_recognition.face_encodings(img2)

        if not enc1 or not enc2:
            return {"match": False, "confidence": 0.0}

        enc1 = enc1[0]
        enc2 = enc2[0]

        # Compare faces
        results = face_recognition.compare_faces([enc1], enc2)
        distance = face_recognition.face_distance([enc1], enc2)[0]

        confidence = 1 - float(distance)

        return {
            "match": bool(results[0]),
            "confidence": round(confidence, 2)
        }

    except Exception as e:
        return {"match": False, "confidence": 0.0}